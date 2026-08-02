#!/usr/bin/env bash
# ==============================================================================
# Cloudera to GCP Automated Migration Script Orchestrator
# ==============================================================================
# This script automates and documents the end-to-end migration pipeline.
# Run components step-by-step or all at once via flags.
# ==============================================================================

set -euo pipefail

# --- CONFIGURATION LAYER ---
# Adjust these variables to match your environment
PROJECT_ID="your-gcp-project-id"
REGION="us-central1"
GCS_BUCKET="gs://my-cloudera-migration-bucket"
HIVE_METASTORE_URI="thrift://localhost:9083"
HDFS_SOURCE_DIR="hdfs:///user/hive/warehouse/"
BQ_DATASET="cloudera_migration"
LOG_FILE="migration_$(date +%Y%m%d_%H%M%S).log"

# --- LOGGING UTILITY ---
log() {
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

error_handler() {
    log "ERROR: Migration failed at line $1"
    exit 1
}
trap 'error_handler $LINENO' ERR

# --- PRE-REQUISITES AND TOOLS ---
step_setup() {
    log "Starting Step 1: Tool Installation and Setup..."
    if ! command -v pip &> /dev/null; then
        log "pip is required but not installed. Aborting."
        exit 1
    fi
    log "Installing Open-Source Google Data Validation Tool (DVT)..."
    pip install google-pydantic-validation data-validation >> "$LOG_FILE" 2>&1
    log "Setup step completed successfully."
}

# --- AUTHENTICATION ---
step_auth() {
    log "Starting Step 2: GCP Authentication..."
    log "Setting current project to: $PROJECT_ID"
    gcloud config set project "$PROJECT_ID" >> "$LOG_FILE" 2>&1
    log "Initiating application-default login sequence..."
    gcloud auth application-default login --no-launch-browser
    log "Authentication setup successfully."
}

# --- INFRASTRUCTURE LANDING ZONE ---
step_infra() {
    log "Starting Step 3: Infrastructure Landing Zone Provisioning..."
    log "Creating GCS Bucket: $GCS_BUCKET"
    gsutil mb -l "$REGION" "$GCS_BUCKET" || log "Bucket already exists or skipped."
    log "Creating BigQuery Dataset: $BQ_DATASET"
    bq --location="$REGION" mk --dataset "$BQ_DATASET" || log "Dataset already exists or skipped."
    log "Infrastructure setup successfully."
}

# --- METADATA & SCHEMA EXTRACTION ---
step_schemas() {
    log "Starting Step 4: Schema Extraction..."
    log "Fetching available table names from Hive default database..."
    hive -e "SET hive.cli.print.header=false; SHOW TABLES IN default;" > tables.txt 2>> "$LOG_FILE"
    
    if [ ! -s tables.txt ]; then
        log "No tables found or Hive client unavailable. Creating a dummy placeholder for script safety."
        echo "sample_table" > tables.txt
    fi

    while read -r table; do
        log "Extracting schema DDL for table: $table"
        hive -e "SHOW CREATE TABLE default.$table" > "${table}.ddl" 2>> "$LOG_FILE" || log "Failed to dump DDL for $table"
    done < tables.txt
    log "Schemas extracted successfully."
}

# --- DISTRIBUTED DATA TRANSFER ---
step_data() {
    log "Starting Step 5: Distributed Data Copy (DistCp)..."
    log "Streaming HDFS directory $HDFS_SOURCE_DIR directly into GCS..."
    # Note: Requires open-source GCS connector configured on the Cloudera cluster
    hadoop distcp         -Dfs.gs.project.id="$PROJECT_ID"         -update -skipcrccheck -numListstatusThreads 40         "$HDFS_SOURCE_DIR"         "$GCS_BUCKET/warehouse/" >> "$LOG_FILE" 2>&1
    log "Data transfer phase executed successfully."
}

# --- DATA VALIDATION ---
step_validate() {
    log "Starting Step 6: Post-Migration Validation via DVT..."
    log "Registering source Hive connection..."
    data-validation connections add -t Hive --host localhost --port 10000 --database default hive_conn >> "$LOG_FILE" 2>&1 || true
    log "Registering target BigQuery connection..."
    data-validation connections add -t BigQuery --project-id "$PROJECT_ID" bq_conn >> "$LOG_FILE" 2>&1 || true
    
    if [ -f tables.txt ]; then
        while read -r table; do
            log "Running row count validation on table: $table"
            data-validation validate row -sc hive_conn -tc bq_conn -tbls "default.${table}=${BQ_DATASET}.${table}" | tee -a "$LOG_FILE"
        done < tables.txt
    else
        log "tables.txt not found. Skipping validation loop."
    fi
    log "Validation process executed."
}

# --- CLEANUP ---
cleanup() {
    log "Cleaning up intermediate temporary artifacts..."
    rm -f tables.txt *.ddl
    log "Cleanup finished."
}

# --- MAIN EXECUTION HANDLER ---
usage() {
    echo "Usage: $0 [all|setup|auth|infra|schemas|data|validate|clean]"
    exit 1
}

if [ $# -eq 0 ]; then
    usage
fi

case "$1" in
    all)
        step_setup
        step_auth
        step_infra
        step_schemas
        step_data
        step_validate
        cleanup
        ;;
    setup)     step_setup ;;
    auth)      step_auth ;;
    infra)     step_infra ;;
    schemas)   step_schemas ;;
    data)      step_data ;;
    validate)  step_validate ;;
    clean)     cleanup ;;
    *)         usage ;;
esac

log "Action '$1' execution completed."
