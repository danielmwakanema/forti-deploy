#!/usr/bin/env bash

set -euo pipefail

# Copernicus DEM GLO-30 downloader
# Downloads 30-meter resolution elevation tiles from AWS S3

SCRIPT_NAME=$(basename "$0")
BASE_URL="https://copernicus-dem-30m.s3.eu-central-1.amazonaws.com"
WORKERS=4

usage() {
    cat << EOF
Usage: $SCRIPT_NAME --lat-min LAT --lat-max LAT --lon-min LON --lon-max LON --output DIR [OPTIONS]

Downloads Copernicus DEM GLO-30 tiles for a bounding box.

Required:
  --lat-min FLOAT    Minimum latitude (south)
  --lat-max FLOAT    Maximum latitude (north)
  --lon-min FLOAT    Minimum longitude (west)
  --lon-max FLOAT    Maximum longitude (east)
  --output DIR       Output directory for .tif files

Optional:
  --workers N        Number of parallel downloads (default: 4)
  --dry-run          Show what would be downloaded without downloading
  --help             Show this help message

Examples:
  # Kenya region
  $SCRIPT_NAME --lat-min -5 --lat-max 5 --lon-min 33 --lon-max 42 --output ./data/topography

  # Malawi region
  $SCRIPT_NAME --lat-min -17 --lat-max -9 --lon-min 32 --lon-max 36 --output ./data/topography

Data source: Copernicus DEM GLO-30 (30m resolution, free and open)
Each 1°×1° tile is approximately 100MB.
Ocean-only tiles may not be available (404/403).
EOF
    exit 0
}

# Parse arguments
LAT_MIN=""
LAT_MAX=""
LON_MIN=""
LON_MAX=""
OUTPUT=""
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --lat-min)
            LAT_MIN="$2"
            shift 2
            ;;
        --lat-max)
            LAT_MAX="$2"
            shift 2
            ;;
        --lon-min)
            LON_MIN="$2"
            shift 2
            ;;
        --lon-max)
            LON_MAX="$2"
            shift 2
            ;;
        --output)
            OUTPUT="$2"
            shift 2
            ;;
        --workers)
            WORKERS="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help)
            usage
            ;;
        *)
            echo "Error: Unknown option: $1" >&2
            echo "Run '$SCRIPT_NAME --help' for usage." >&2
            exit 1
            ;;
    esac
done

# Validate required arguments
if [[ -z "$LAT_MIN" || -z "$LAT_MAX" || -z "$LON_MIN" || -z "$LON_MAX" || -z "$OUTPUT" ]]; then
    echo "Error: Missing required arguments" >&2
    echo "Run '$SCRIPT_NAME --help' for usage." >&2
    exit 1
fi

# Format tile name from lat/lon coordinates
# Tiles are named by their southwest corner
# Format: Copernicus_DSM_COG_10_N00_00_E040_00_DEM
format_tile_name() {
    local lat=$1
    local lon=$2
    local lat_str lon_str
    
    # Format latitude
    if [[ $lat -ge 0 ]]; then
        lat_str=$(printf "N%02d_00" "$lat")
    else
        lat_str=$(printf "S%02d_00" $((-lat)))
    fi
    
    # Format longitude
    if [[ $lon -ge 0 ]]; then
        lon_str=$(printf "E%03d_00" "$lon")
    else
        lon_str=$(printf "W%03d_00" $((-lon)))
    fi
    
    echo "Copernicus_DSM_COG_10_${lat_str}_${lon_str}_DEM"
}

# Generate list of tile names for bounding box
generate_tiles() {
    local lat_min=$1
    local lat_max=$2
    local lon_min=$3
    local lon_max=$4
    
    # Floor the coordinates to get tile indices
    lat_min=$(printf "%.0f" "$lat_min" | awk '{print int($1)}')
    lat_max=$(printf "%.0f" "$lat_max" | awk '{print int($1)}')
    lon_min=$(printf "%.0f" "$lon_min" | awk '{print int($1)}')
    lon_max=$(printf "%.0f" "$lon_max" | awk '{print int($1)}')
    
    for lat in $(seq "$lat_min" "$lat_max"); do
        for lon in $(seq "$lon_min" "$lon_max"); do
            format_tile_name "$lat" "$lon"
        done
    done
}

# Download a single tile
download_tile() {
    local tile_name=$1
    local output_dir=$2
    local file_name="${tile_name}.tif"
    local url="${BASE_URL}/${tile_name}/${file_name}"
    local dest_path="${output_dir}/${file_name}"
    
    # Check if file already exists
    if [[ -f "$dest_path" ]]; then
        # Verify it's complete by checking if we can get HEAD
        local remote_size
        remote_size=$(curl -sI "$url" | grep -i "content-length:" | awk '{print $2}' | tr -d '\r')
        local local_size
        local_size=$(stat -f%z "$dest_path" 2>/dev/null || stat -c%s "$dest_path" 2>/dev/null || echo "0")
        
        if [[ "$remote_size" == "$local_size" ]]; then
            echo "  ✓ $file_name (already downloaded)"
            return 0
        fi
    fi
    
    # Download the file
    local http_code
    http_code=$(curl -sS -w "%{http_code}" -o "$dest_path.tmp" "$url")
    
    case $http_code in
        200)
            mv "$dest_path.tmp" "$dest_path"
            echo "  ✓ $file_name"
            return 0
            ;;
        404|403)
            rm -f "$dest_path.tmp"
            echo "  ⊘ $file_name (not available - likely ocean)"
            return 0
            ;;
        *)
            rm -f "$dest_path.tmp"
            echo "  ✗ $file_name (HTTP $http_code)" >&2
            return 1
            ;;
    esac
}

export -f download_tile format_tile_name
export BASE_URL

# Main execution
echo "Bounding box: lat [$LAT_MIN, $LAT_MAX], lon [$LON_MIN, $LON_MAX]"

# Generate tile list
TILES=$(generate_tiles "$LAT_MIN" "$LAT_MAX" "$LON_MIN" "$LON_MAX")
TILE_COUNT=$(echo "$TILES" | wc -l | tr -d ' ')

echo "Found $TILE_COUNT tiles to download"

if $DRY_RUN; then
    echo ""
    echo "DRY RUN - would download:"
    echo "$TILES" | while read -r tile; do
        echo "  $tile"
    done
    echo ""
    echo "Output directory: $OUTPUT"
    exit 0
fi

# Create output directory
mkdir -p "$OUTPUT"

echo ""
echo "Downloading to: $OUTPUT"
echo "Using $WORKERS parallel workers"
echo ""

# Download tiles in parallel
echo "$TILES" | xargs -I {} -P "$WORKERS" bash -c "download_tile '{}' '$OUTPUT'"

echo ""
echo "Download complete!"
echo "Output: $OUTPUT"
