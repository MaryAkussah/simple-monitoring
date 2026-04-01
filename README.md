# Simple Monitoring with Netdata

This project automates a basic Netdata setup on a Linux host and covers the project requirements:

- Install Netdata on Linux
- Monitor CPU, memory, and disk I/O
- Access the dashboard in a browser on port `19999`
- Add a custom dashboard chart
- Add a CPU usage alert
- Exercise the dashboard with a repeatable load test
- Remove the setup cleanly

## Files

- `setup.sh`: installs Netdata, enables a custom chart, and adds a CPU alert
- `test_dashboard.sh`: generates CPU, memory, and disk activity so the dashboard has visible changes
- `cleanup.sh`: removes the custom monitoring bits and uninstalls the Netdata agent
- `netdata/custom_load.chart.sh`: a custom `charts.d` collector that adds a new chart to the dashboard
- `netdata/custom_load.conf`: collector settings used by the custom chart
- `netdata/custom_cpu_alert.conf`: custom health alarm for sustained CPU usage above 80%

- Project Url :https://roadmap.sh/projects/simple-monitoring-dashboard

## Quick Start

Run these commands on a Linux machine:

```bash
chmod +x setup.sh test_dashboard.sh cleanup.sh
sudo ./setup.sh
sudo ./test_dashboard.sh
```

Then open:

```text
http://<your-linux-host>:19999
```

If you are testing on the same host, `http://localhost:19999` works.

## What Gets Configured

`setup.sh` installs Netdata using the official `kickstart.sh` installer in non-interactive mode on the stable release channel, then adds:

- A custom chart called `custom_load.synthetic` that visualizes the synthetic load test state
- A custom CPU alert that warns above `80%` and goes critical above `90%`

Netdata already collects CPU, memory, and disk I/O by default, so no extra collector setup is needed for those core system metrics.

## Testing the Dashboard

`test_dashboard.sh` does three things at the same time:

- Starts CPU workers with `yes > /dev/null`
- Reserves memory by writing a file into `/dev/shm` when available
- Repeatedly writes and flushes a test file to generate disk I/O

While it runs, you should see activity on the built-in charts and on the custom `Synthetic Load Test Activity` chart.

You can tune the load with environment variables:

```bash
CPU_WORKERS=4 DURATION_SECONDS=90 sudo ./test_dashboard.sh
```

## Cleanup

To remove the Netdata agent and the custom files:

```bash
sudo ./cleanup.sh
```

## Notes

- These scripts are written for Linux and expect `bash`, `curl`, `systemctl`, and standard coreutils.
- The setup script automatically tries to install `netdata-plugin-chartsd` when the `charts.d` plugin is not present, because that plugin is not bundled in Netdata's native DEB/RPM packages by default.
- If you are using a remote host, make sure TCP port `19999` is reachable from your browser.
