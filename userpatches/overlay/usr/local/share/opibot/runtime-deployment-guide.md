# OPiBot Runtime Deployment Guide

This image is a reusable base image. ROS 2 Humble is preinstalled as middleware, but concrete business services are expected to be deployed after the image boots.

## 1. Runtime Model

The base image provides these systemd targets:

1. `opibot-base.target`: common platform services and middleware base.
2. `opibot-perception.target`: perception and state-estimation workloads.
3. `opibot-control.target`: control-loop and actuator-facing workloads.
4. `opibot-planning.target`: low-frequency but compute-heavy planning or optimization workloads.
5. `opibot-mission.target`: composed runtime target that can pull in both perception and control workloads.

Runtime modes are controlled through `/usr/local/sbin/opibot-runtime-mode`:

1. `standby`: low-power standby.
2. `perception-active`: perception-heavy operation. It keeps the high-performance CPU policy, but restores generic IRQ balancing for throughput-oriented workloads.
3. `control-active`: control-loop operation. It keeps the high-performance CPU policy and applies RT-directed IRQ tuning for latency-sensitive workloads.

The current default base image configuration tracks actual workloads through `opibot-mission.target`, not by the presence of ROS 2 alone.

## 2. Service Placement Rules

Use these rules when deploying runtime business services:

1. Put hardware-control loops, actuator bridges, and strict latency tasks under `opibot-control.target`.
2. Put VIO, SLAM frontends, camera pipelines, lidar pipelines, and similar throughput-oriented tasks under `opibot-perception.target`.
3. Put low-frequency but high-compute planning, optimization, or route-selection services under `opibot-planning.target` unless they are tightly coupled to a perception pipeline.
4. Put logging, telemetry, visualization bridges, remote access helpers, and support daemons under `opibot-base.target` or regular system targets.
5. Use `opibot-mission.target` as the single operator-facing target when a mission should bring up the full workload stack.

Do not bind all ROS 2 services to the same target by default. Split them by control, perception, and support roles first.

## 3. Recommended Deployment Layout

Recommended runtime layout:

1. Install project-specific unit files under `/etc/systemd/system`.
2. Keep project launch scripts under `/usr/local/bin` or project-owned package paths.
3. Store project configuration under `/etc/<project>` or `/opt/<project>/config`.
4. Keep the base image files under `/etc/default/opibot-*` unchanged unless you are intentionally changing platform policy.

Service-domain policy is controlled through `/etc/default/opibot-service-layout` and applied by `/usr/local/sbin/opibot-service-layout`:

1. `CONTROL_SERVICES`: high-frequency control loops, actuator bridges, hard real-time helpers.
2. `PERCEPTION_SERVICES`: camera, lidar, VIO, SLAM frontends, and similar throughput-heavy services.
3. `PLANNING_SERVICES`: low-frequency but high-compute planning or optimization services that should stay off the dedicated control CPUs.
4. `SUPPORT_SERVICES`: logging, telemetry, UI bridges, remote ops, and similar background services.

The default domain policy keeps `CONTROL_CPUS=6,7`, `PERCEPTION_CPUS=4-5`, and `SYSTEM_CPUS=0-3`. Planning services default to the perception domain unless you intentionally widen them.

## 4. Example Service Pattern

Example control service:

```ini
[Unit]
Description=My control loop
PartOf=opibot-control.target
After=opibot-control-prepare.service
Wants=opibot-control-prepare.service

[Service]
Type=simple
ExecStart=/usr/local/bin/my-control-launch
Restart=on-failure
CPUAffinity=6 7

[Install]
WantedBy=opibot-control.target
```

Example perception service:

```ini
[Unit]
Description=My perception stack
PartOf=opibot-perception.target
After=opibot-perception-prepare.service
Wants=opibot-perception-prepare.service

[Service]
Type=simple
ExecStart=/usr/local/bin/my-perception-launch
Restart=on-failure
CPUAffinity=4 5

[Install]
WantedBy=opibot-perception.target
```

Example service-domain policy:

```bash
CONTROL_SERVICES="my-control.service"
PERCEPTION_SERVICES="camera-pipeline.service slam-frontend.service"
PLANNING_SERVICES="global-planner.service"
SUPPORT_SERVICES="telemetry-bridge.service web-console.service"
```

Example mission aggregator:

```ini
[Unit]
Description=My mission target
Wants=opibot-mission.target my-control.service my-perception.service
After=opibot-mission.target my-control.service my-perception.service
```

Example planning service:

```ini
[Unit]
Description=My planner
PartOf=opibot-planning.target
After=opibot-planning-prepare.service
Wants=opibot-planning-prepare.service

[Service]
Type=simple
ExecStart=/usr/local/bin/my-planner-launch
Restart=on-failure
CPUAffinity=4 5

[Install]
WantedBy=opibot-planning.target
```

## 5. ROS 2 Middleware Selection

This image installs multiple ROS 2 Humble RMW implementations so you can choose transport behavior at runtime instead of rebuilding the image.

Installed options:

1. `rmw_cyclonedds_cpp`: low-friction default for DDS-based local and LAN deployments.
2. `rmw_zenoh_cpp`: alternative transport for Zenoh-based deployments.

Use one of the following environment selections before starting ROS 2 nodes or services:

```bash
export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
```

```bash
export RMW_IMPLEMENTATION=rmw_zenoh_cpp
```

For Zenoh-based deployments, remember these runtime expectations:

1. A Zenoh router is usually required for discovery with the default configuration.
2. You can start a local router with `ros2 run rmw_zenoh_cpp rmw_zenohd`.
3. If you intentionally run without a router, set `ZENOH_ROUTER_CHECK_ATTEMPTS=-1` and provide an explicit Zenoh configuration override appropriate for your topology.
4. `rmw_zenoh_cpp` is an alternative RMW, not a drop-in wire-level bridge for DDS traffic.

## 6. Deployment Procedure

1. Copy or install your business binaries, launch scripts, and unit files onto the running system.
2. Run `systemctl daemon-reload`.
3. Enable your services against the correct OPiBot target.
4. Start the narrowest target that matches the workload you need.
5. Verify that mode switching and CPU placement match the intended role.
6. If you changed `/etc/default/opibot-service-layout`, run `sudo /usr/local/sbin/opibot-service-layout apply-config` before starting workload targets.

Typical commands:

```bash
export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
sudo systemctl daemon-reload
sudo systemctl enable my-control.service
sudo systemctl enable my-perception.service
sudo systemctl enable my-planner.service
sudo systemctl start opibot-control.target
sudo systemctl start opibot-perception.target
sudo systemctl start opibot-planning.target
sudo systemctl start opibot-mission.target
sudo /usr/local/sbin/opibot-runtime-mode status
sudo /usr/local/sbin/opibot-irq-layout status
```

If you need Zenoh for a deployment or test session:

```bash
export RMW_IMPLEMENTATION=rmw_zenoh_cpp
ros2 run rmw_zenoh_cpp rmw_zenohd
```

## 7. Verification Checklist

After deploying runtime business services, verify:

1. `systemctl status opibot-base.target opibot-perception.target opibot-control.target opibot-planning.target opibot-mission.target`
2. `systemctl status <your-service-name>`
3. `journalctl -u opibot-runtime-mode.service -u opibot-runtime-autoswitch.service --no-pager`
4. `taskset -pc <pid>` for critical processes.
5. `systemctl status irqbalance` to confirm the expected runtime mode behavior.
6. `systemctl show <your-service-name> -p Slice -p CPUAffinity`
7. `echo $RMW_IMPLEMENTATION` before starting ROS 2 services in a manual shell.

## 8. Overlay Build Notes

This image currently uses `OVERLAY_MERGE=partial` by default. If you customize `OVERLAY_WHITELIST`, make sure it still includes the required OPiBot paths, especially:

1. `etc/default`
2. `etc/systemd/system`
3. `usr/local/sbin`
4. `usr/local/share/opibot`

If `usr/local/share/opibot` is omitted from a custom whitelist, this guide will not be copied into the image and the build-time document installation step will only emit a warning.