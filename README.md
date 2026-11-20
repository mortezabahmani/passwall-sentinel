# passwall-sentinel 🛡️⚡
> **Intelligent Failsafe Watchdog & Isolated Benchmark Engine for OpenWrt & PassWall 2**  
> *Self-healing autopilot with zero-downtime armed rollback, emergency bypass protection, and a 50-provider direct DNS auditor.*

[![OpenWrt](https://img.shields.io/badge/OpenWrt-19.07%20--%2025.x%2B-blue.svg?logo=openwrt&logoColor=white)](https://openwrt.org)
[![Platform](https://img.shields.io/badge/Architecture-Universal%20(ARM%20%7C%20MIPS%20%7C%20x86)-orange.svg)]()
[![Interface](https://img.shields.io/badge/LuCI-Modern%20JS%20Web%20UI-green.svg)]()
[![License: CC BY-NC-SA 4.0](https://img.shields.io/badge/License-CC%20BY--NC--SA%204.0-red.svg)](LICENSE)

[**فارسی (Persian Documentation)**](README.fa.md)

---

## 🎯 The Real-World Scenario: What Problem Does It Solve?

You set up an OpenWrt router at home or the office with **PassWall 2** so that all connected devices (smartphones, TVs, laptops) seamlessly access unfiltered internet without client-side VPN apps. In everyday practice, you inevitably run into four painful frustrations:

1. **The 3 AM Silent Blackout:**  
   The active proxy node gets blocked or throttled in the middle of the night. Every connected user wakes up to "No Internet" on their devices until someone logs into LuCI to manually test and select a working node.
2. **The 4-Second DNS Lag (Poisoning & Slow DoH):**  
   Websites take several seconds just to begin resolving (`TTFB`). This is caused by unencrypted UDP port 53 packets being silently injected with fake IPs (DNS Poisoning) or misconfigured remote DoH servers taking 1.5+ seconds to reply.
3. **The Low-Power Router Trap (CPU Throttling):**  
   An imported subscription defaults to a heavy protocol like gRPC or QUIC/Hysteria2. Your router's modest 716 MHz MIPS/ARM CPU cannot handle userspace multi-stream encryption; it overheats, spikes load averages, and drops packets.
4. **The Dread of Breaking Router Settings:**  
   One wrong click in LuCI firewall or proxy rules locks you out of the router entirely, forcing you to find a paperclip and factory-reset the device.

### 💡 How PassWall Sentinel Solves This:
* **Autonomous Network Co-Pilot:** Benchmarks all subscription nodes and 50 curated DNS providers **100% directly over physical WAN** (using firewall socket mark 255) — completely isolated from the active proxy tunnel.
* **Armed Rollback Guarantee:** Every configuration change is verified by an automated 60-second health check. If internet connectivity fails, it reverts immediately to the previous working snapshot.
* **Emergency Bypass Watchdog:** If PassWall freezes, crashes, or suffers a complete network blackout, Sentinel's watchdog disables it within seconds, restoring direct internet so you never lose connection to your router.
* **Hardware-Aware Scoring Algorithm:** Automatically penalizes CPU-punishing protocols on low-power ARMv7/MIPS routers, boosting lightweight protocols like VLESS-Reality and ChaCha20.

---

## 🔍 How It Works: Source of Nodes & Applied Settings

PassWall Sentinel is built to integrate seamlessly with OpenWrt's native **UCI (Unified Configuration Interface)**, avoiding duplication and keeping everything in sync with the official PassWall 2 web interface:

### 1. Where do the nodes come from? (Source)
You do **not** need to re-enter your subscription link inside this tool!
* You enter and update your subscription links inside PassWall 2 as usual:  
  `LuCI -> Services -> PassWall 2 -> Node Subscribe`
* PassWall automatically fetches, decodes, and populates the nodes into OpenWrt's UCI configuration at `/etc/config/passwall2`.
* **Sentinel reads directly from this list**, parsing server endpoints, ports, protocols, and transports for isolated benchmarking.

### 2. Where are the changes applied? (Target)
Upon user confirmation (or automatically if auto-apply is enabled), Sentinel updates the following official PassWall 2 UCI variables:
* **Default Proxy Node:** Updates `default_node` in PassWall's rule node section (`passwall2.rulenode.default_node`).  
  *(Visible in LuCI under `Services -> PassWall 2 -> Basic Settings -> Main Node`).*
* **Remote Secure DoH DNS:** Updates `remote_dns_doh` (`passwall2.@global[0].remote_dns_doh`) with the fastest benchmarked DoH resolver.  
  *(Visible in LuCI under `Services -> PassWall 2 -> DNS Settings -> Remote DNS`).*
* **Commit & Zero-Downtime Reload:** Saves via `uci commit passwall2` and executes `/etc/init.d/passwall2 reload`, swapping the active tunnel in memory in under a second without resetting firewall tables or restarting physical network interfaces.

---

## 📊 Real-World Case Study: Benchmarked on a 716 MHz Router

To measure the real-world impact of Sentinel's optimization, tests were conducted on an entry-level quad-core ARM Cortex-A7 router running at 716 MHz with 512 MB RAM:

| Metric | Before Optimization (Unoptimized Node & DoH) | After Sentinel Optimization (Tuned Node & DoH) | Impact |
| :--- | :--- | :--- | :--- |
| **Active Protocol** | Trojan via gRPC (Heavy multiplexing & CPU overhead) | VLESS via WebSocket + TLS (Lightweight framing) | **Drastic reduction in router CPU load** |
| **Initial Load (TTFB)** | 3,543 ms (~3.5 seconds waiting for first byte) | **712 ms** | **~5x faster page loading speed** |
| **Network Jitter / Ping**| Erratic ping between 230 ms and 429 ms | **118 ms** (rock solid) | **>2x lower and more stable latency** |
| **Download Throughput** | 11.7 Mbps | **22.8 Mbps** | **~2x bandwidth throughput increase** |
| **Remote DNS Latency** | 1,711 ms (Default DoH server was slow/throttled) | **665 ms** (Optimal direct DoH provider) | **Saved >1 second on every domain resolution** |
| **UDP DNS Poisoning** | Undetected fake IP injection on port 53 | **Detected and flagged fake IPs automatically** | **Prevents censorship blocks and connection drops** |

---

## 🏗️ System Architecture

```
                    [Physical WAN Network Interface]
                                  │ (SO_MARK = 255 - 100% Direct Route)
                                  ▼
        ┌──────────────────────────────────────────────────┐
        │             passwall-sentinel Engine             │
        ├────────────────────────┬─────────────────────────┤
        │ 1. Direct DNS Auditor  │ 2. Isolated Node Screen │
        │    (50 Servers / Fake) │    (TCP Ping + TTFB)    │
        └────────────────────────┴─────────────────────────┘
                                  │
                                  ▼
                     [Hardware Scoring Engine]
                                  │
             ┌────────────────────┴────────────────────┐
             ▼                                         ▼
      [Manual Review]                          [Auto-Apply Mode]
   (View in LuCI Web UI)                   (Armed 60s Rollback Timer)
                                                       │
                                       ┌───────────────┴───────────────┐
                                       ▼                               ▼
                               [Verified Online]             [Auto-Rollback Snapshot]
                                (Keep Settings)                (Revert in 4 seconds)
```

---

## 🚀 Installation

### 1. Single-Command Quick Install (Recommended)

Connect to your OpenWrt router via SSH and run:

```sh
curl -sSL https://raw.githubusercontent.com/mortezabahmani/passwall-sentinel/main/install.sh | sh
```

### 2. Private Repository / Git Clone Install

```sh
git clone git@github.com:mortezabahmani/passwall-sentinel.git
cd passwall-sentinel
sh install.sh
```

---

## 🖥️ Web User Interface (LuCI)

Navigate to **Services ➔ PassWall Sentinel** in your OpenWrt web interface:
* Direct URL: `http://192.168.1.1/cgi-bin/luci/admin/services/pwsentinel`

### Web Dashboard Features:
1. **Live Status Cards:** Displays active PassWall 2 node, active DoH DNS, last benchmark time, and current protection mode.
2. **`⚡ Run Benchmark Now` Button:** Executes an isolated benchmark on-demand and shows live terminal output in an interactive modal.
3. **`✅ Apply Recommendation` Button:** Applies the winning node and DoH DNS with a 60-second armed rollback failsafe.
4. **`⏪ Rollback Snapshot` Button:** Instantly reverts to the previous configuration.
5. **Node Benchmark Ranking Table:** Displays rank, node remarks, protocol, direct TCP ping, real TTFB, and hardware score.
6. **50 Direct DNS Table:** Displays raw UDP 53 latency, poisoning flags (fake IP detection), TCP 53, and DoH 443 response times.

---

## 💻 CLI Commands

| Command | Description |
| :--- | :--- |
| `pwsentinel check` | Full isolated benchmark (Nodes + 50 DNS) & save report |
| `pwsentinel status` | View current active state and recommendations |
| `pwsentinel apply` | Safely apply recommended node & DNS with armed rollback |
| `pwsentinel rollback` | Revert PassWall 2 to previous safety snapshot |
| `pwsentinel test-nodes` | Benchmark PassWall 2 nodes only |
| `pwsentinel test-dns` | Benchmark 50 direct DNS servers only |
| `pwsentinel failsafe` | Manually trigger health watchdog check |

---

## ⚙️ Advanced Configuration (`/etc/config/pwsentinel`)

```uci
config settings 'main'
    option enabled '1'                     # 1: Enable Sentinel background service
    option auto_apply '0'                  # 0: Manual approval | 1: Automatic apply
    option check_interval '6h'             # Schedule: 1h, 2h, 6h, 12h, 1d, 1w
    option max_nodes_to_test '5'           # Top candidate nodes to test deeply
    option failsafe_enabled '1'            # Emergency bypass watchdog
    option failsafe_loss_threshold '3'     # Failures before emergency bypass
    option bypass_mark '255'               # Socket mark for direct WAN traffic
    option direct_interface 'wan'          # Physical raw WAN interface
```

---

## 📄 License

This project is licensed under the **Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International (CC BY-NC-SA 4.0)** license:

- **✅ Free to Use & Modify:** You are welcome to use, adapt, and build upon this code for personal, community, and non-commercial projects.
- **🚫 Strictly Non-Commercial:** No one is permitted to sell, monetize, or bundle this software or derivative works for commercial advantage or monetary compensation.
- **🔗 Attribution Required:** Any reuse, modification, or inclusion in other projects must retain clear attribution to the original creator (**Morteza Bahmani**) and a link to this repository ([mortezabahmani/passwall-sentinel](https://github.com/mortezabahmani/passwall-sentinel)).
- **🔄 ShareAlike:** If you alter, transform, or build upon the material, you must distribute your contributions under the same CC BY-NC-SA 4.0 license.

For the full legal code, see the [LICENSE](LICENSE) file.
