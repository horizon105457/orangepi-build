#!/bin/bash
# Complete RT Latency Test Suite for RK3588s
# Tests real-time kernel performance with comprehensive logging
# Usage: sudo rt-latency-test.sh [duration_seconds] [output_dir]

set -euo pipefail

# Configuration
DURATION=${1:-60}           # Test duration in seconds
OUTPUT_DIR=${2:-"/var/log/rt-tests"}
RT_CPUS="6,7"              # RK3588s RT cores
BG_CPUS="0-5"              # Background cores
TEST_INTERVAL=1000         # cyclictest interval (μs)
HISTOGRAM_RES=100          # Histogram resolution (μs)
PRIORITY=99                # RT priority

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Log file
LOGFILE="${OUTPUT_DIR}/rt_test_$(date +%Y%m%d_%H%M%S).log"
SUMMARY_FILE="${OUTPUT_DIR}/rt_test_summary.txt"

# Helper functions
log() {
	local level=$1
	shift
	local msg="$*"
	local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
	echo -e "[${timestamp}] [${level}] ${msg}" | tee -a "$LOGFILE"
}

log_info() { log "INFO" "$@"; }
log_warn() { log "WARN" "$@"; }
log_error() { log "ERROR" "$@"; }
log_success() { log "SUCCESS" "$@"; }

print_header() {
	echo -e "\n${BLUE}============================================${NC}" | tee -a "$LOGFILE"
	echo -e "${BLUE}$1${NC}" | tee -a "$LOGFILE"
	echo -e "${BLUE}============================================${NC}\n" | tee -a "$LOGFILE"
}

print_result() {
	local test_name=$1
	local avg=$2
	local max=$3
	local status="PASS"

	# Thresholds (in μs)
	if (( $(echo "$max > 1000" | bc -l) )); then
		status="WARN"
	fi
	if (( $(echo "$max > 2000" | bc -l) )); then
		status="FAIL"
	fi

	case $status in
		PASS)
			echo -e "${GREEN}✓ $test_name: avg=${avg}μs, max=${max}μs${NC}" | tee -a "$LOGFILE"
			;;
		WARN)
			echo -e "${YELLOW}⚠ $test_name: avg=${avg}μs, max=${max}μs (Warning: High latency)${NC}" | tee -a "$LOGFILE"
			;;
		FAIL)
			echo -e "${RED}✗ $test_name: avg=${avg}μs, max=${max}μs (FAILED: Unacceptable latency)${NC}" | tee -a "$LOGFILE"
			;;
	esac

	echo "$test_name,$avg,$max,$status" >> "$SUMMARY_FILE"
}

# Check prerequisites
check_prerequisites() {
	print_header "Checking Prerequisites"

	# Check if running as root
	if [[ $EUID -ne 0 ]]; then
		log_error "Must run as root"
		exit 1
	fi
	log_success "Running as root"

	# Check required tools
	local required_tools=("cyclictest" "stress-ng" "bc")
	for tool in "${required_tools[@]}"; do
		if ! command -v "$tool" &> /dev/null; then
			log_warn "$tool not found, some tests will be skipped"
		else
			log_success "$tool available"
		fi
	done

	# Check if RT kernel is running
	if grep -q "PREEMPT_RT" /boot/config-* 2>/dev/null || grep -q "RT" /proc/version 2>/dev/null; then
		log_success "RT kernel detected"
	else
		log_warn "RT kernel not detected - some results may not be representative"
	fi
}

# Log system information
log_system_info() {
	print_header "System Information"

	echo "Hostname: $(hostname)" | tee -a "$LOGFILE"
	echo "Kernel: $(uname -r)" | tee -a "$LOGFILE"
	echo "CPU Model: $(lscpu | grep 'Model name' | cut -d: -f2 | xargs)" | tee -a "$LOGFILE"
	echo "CPU Cores: $(nproc)" | tee -a "$LOGFILE"
	echo "Total Memory: $(free -h | grep Mem | awk '{print $2}')" | tee -a "$LOGFILE"
	echo "Available Memory: $(free -h | grep Mem | awk '{print $7}')" | tee -a "$LOGFILE"
	echo "Uptime: $(uptime -p)" | tee -a "$LOGFILE"
	echo "" | tee -a "$LOGFILE"
}

# Log RT configuration
log_rt_config() {
	print_header "RT Kernel Configuration"

	echo "RT CPUs (isolated): $RT_CPUS" | tee -a "$LOGFILE"
	echo "Background CPUs: $BG_CPUS" | tee -a "$LOGFILE"
	echo "" | tee -a "$LOGFILE"

	echo "=== Kernel Parameters ===" | tee -a "$LOGFILE"
	sysctl kernel.sched_rt_runtime_us | tee -a "$LOGFILE"
	sysctl kernel.sched_rt_period_us | tee -a "$LOGFILE"
	sysctl kernel.sched_min_granularity_ns | tee -a "$LOGFILE"
	sysctl vm.swappiness | tee -a "$LOGFILE"
	sysctl net.core.default_qdisc | tee -a "$LOGFILE"
	echo "" | tee -a "$LOGFILE"

	# Check CPU governor
	echo "=== CPU Governors ===" | tee -a "$LOGFILE"
	for cpu in $(seq 0 $(($(nproc)-1))); do
		gov=$(cat /sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_governor 2>/dev/null || echo "N/A")
		freq=$(cat /sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_cur_freq 2>/dev/null || echo "N/A")
		echo "CPU$cpu: governor=$gov, freq=$freq" | tee -a "$LOGFILE"
	done
	echo "" | tee -a "$LOGFILE"
}

# Test 1: Baseline latency (no load)
test_baseline() {
	print_header "Test 1: Baseline Latency (No Load)"

	log_info "Running cyclictest for $DURATION seconds on cores $RT_CPUS..."

	local hist_file="${OUTPUT_DIR}/baseline_histogram.txt"
	local raw_file="${OUTPUT_DIR}/baseline_raw.txt"

	if command -v cyclictest &> /dev/null; then
		cyclictest \
			-p $PRIORITY \
			-m \
			-a $RT_CPUS \
			-i $TEST_INTERVAL \
			-l $((DURATION * 1000)) \
			-h $HISTOGRAM_RES \
			-q \
			--histfile="$hist_file" \
			> "$raw_file" 2>&1 || true

		local max_latency=$(awk '{print $2}' "$hist_file" | tail -n +2 | sort -n | tail -1)
		avg_latency=$(awk 'NR>1 {s+=$2; c++} END {if (c>0) printf "%.0f", s/c}' "$hist_file")

		print_result "Baseline (No Load)" "$avg_latency" "$max_latency"

		log_info "Histogram saved to: $hist_file"
		log_info "Raw output saved to: $raw_file"
	else
		log_error "cyclictest not available"
	fi
}

# Test 2: CPU stress load
test_cpu_stress() {
	print_header "Test 2: Latency Under CPU Stress"

	log_info "Generating CPU stress on background cores..."

	local hist_file="${OUTPUT_DIR}/cpu_stress_histogram.txt"
	local raw_file="${OUTPUT_DIR}/cpu_stress_raw.txt"

	# Start stress in background
	if command -v stress-ng &> /dev/null; then
		stress-ng \
			--cpu 4 \
			--io 1 \
			--timeout ${DURATION}s \
			--quiet &
		local stress_pid=$!

		sleep 1  # Let stress settle

		# Run cyclictest during stress
		cyclictest \
			-p $PRIORITY \
			-m \
			-a $RT_CPUS \
			-i $TEST_INTERVAL \
			-l $((DURATION * 1000)) \
			-h $HISTOGRAM_RES \
			-q \
			--histfile="$hist_file" \
			> "$raw_file" 2>&1 || true

		wait $stress_pid 2>/dev/null || true

		local max_latency=$(awk '{print $2}' "$hist_file" | tail -n +2 | sort -n | tail -1)
		local avg_latency=$(awk 'NR>1 {s+=$2; c++} END {if (c>0) printf "%.0f", s/c}' "$hist_file")

		print_result "CPU Stress" "$avg_latency" "$max_latency"

		log_info "Histogram saved to: $hist_file"
	else
		log_warn "stress-ng not available, skipping CPU stress test"
	fi
}

# Test 3: Memory pressure
test_memory_stress() {
	print_header "Test 3: Latency Under Memory Stress"

	log_info "Generating memory pressure..."

	local hist_file="${OUTPUT_DIR}/memory_stress_histogram.txt"
	local raw_file="${OUTPUT_DIR}/memory_stress_raw.txt"

	if command -v stress-ng &> /dev/null; then
		# Get available memory (leave 500MB free)
		local total_mem=$(free -b | awk 'NR==2 {print int(($2 - 500000000) / 1024 / 1024) "M"}')

		stress-ng \
			--vm 2 \
			--vm-bytes "$total_mem" \
			--timeout ${DURATION}s \
			--quiet &
		local stress_pid=$!

		sleep 1

		cyclictest \
			-p $PRIORITY \
			-m \
			-a $RT_CPUS \
			-i $TEST_INTERVAL \
			-l $((DURATION * 1000)) \
			-h $HISTOGRAM_RES \
			-q \
			--histfile="$hist_file" \
			> "$raw_file" 2>&1 || true

		wait $stress_pid 2>/dev/null || true

		local max_latency=$(awk '{print $2}' "$hist_file" | tail -n +2 | sort -n | tail -1)
		local avg_latency=$(awk 'NR>1 {s+=$2; c++} END {if (c>0) printf "%.0f", s/c}' "$hist_file")

		print_result "Memory Stress" "$avg_latency" "$max_latency"

		log_info "Histogram saved to: $hist_file"
	else
		log_warn "stress-ng not available, skipping memory stress test"
	fi
}

# Test 4: Combined stress
test_combined_stress() {
	print_header "Test 4: Latency Under Combined Stress (CPU + Memory + I/O)"

	log_info "Generating combined stress load..."

	local hist_file="${OUTPUT_DIR}/combined_stress_histogram.txt"
	local raw_file="${OUTPUT_DIR}/combined_stress_raw.txt"

	if command -v stress-ng &> /dev/null; then
		local total_mem=$(free -b | awk 'NR==2 {print int(($2 - 500000000) / 1024 / 1024) "M"}')

		stress-ng \
			--cpu 3 \
			--vm 1 \
			--vm-bytes "$total_mem" \
			--io 2 \
			--timeout ${DURATION}s \
			--quiet &
		local stress_pid=$!

		sleep 1

		cyclictest \
			-p $PRIORITY \
			-m \
			-a $RT_CPUS \
			-i $TEST_INTERVAL \
			-l $((DURATION * 1000)) \
			-h $HISTOGRAM_RES \
			-q \
			--histfile="$hist_file" \
			> "$raw_file" 2>&1 || true

		wait $stress_pid 2>/dev/null || true

		local max_latency=$(awk '{print $2}' "$hist_file" | tail -n +2 | sort -n | tail -1)
		local avg_latency=$(awk 'NR>1 {s+=$2; c++} END {if (c>0) printf "%.0f", s/c}' "$hist_file")

		print_result "Combined Stress" "$avg_latency" "$max_latency"

		log_info "Histogram saved to: $hist_file"
	else
		log_warn "stress-ng not available, skipping combined stress test"
	fi
}

# Generate summary report
generate_summary() {
	print_header "Test Summary Report"

	if [ -f "$SUMMARY_FILE" ]; then
		echo "Test,Avg Latency (μs),Max Latency (μs),Status" > "${SUMMARY_FILE}.tmp"
		cat "$SUMMARY_FILE" >> "${SUMMARY_FILE}.tmp"
		mv "${SUMMARY_FILE}.tmp" "$SUMMARY_FILE"

		log_success "Summary report saved to: $SUMMARY_FILE"
		echo "" | tee -a "$LOGFILE"
		cat "$SUMMARY_FILE" | tee -a "$LOGFILE"
	fi
}

# Main execution
main() {
	log_info "Starting RT Latency Test Suite"
	log_info "Output directory: $OUTPUT_DIR"
	log_info "Log file: $LOGFILE"
	log_info "Test duration: $DURATION seconds per test"
	echo "" | tee -a "$LOGFILE"

	# Clear summary file
	> "$SUMMARY_FILE"

	# Run all checks and tests
	check_prerequisites
	log_system_info
	log_rt_config
	test_baseline
	test_cpu_stress
	test_memory_stress
	test_combined_stress
	generate_summary

	print_header "Test Suite Completed"
	log_success "All tests completed. Results saved to $OUTPUT_DIR"
	log_info "View summary: cat $SUMMARY_FILE"
	log_info "View full log: tail -f $LOGFILE"
}

# Run main
main "$@"
