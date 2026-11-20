# passwall-sentinel 🛡️⚡
> **Intelligent Failsafe Watchdog & Isolated Benchmark Engine for OpenWrt & PassWall 2**  
> *Autonomous node and 50 direct DNS benchmark engine with zero-downtime armed rollback and emergency bypass protection.*

[![OpenWrt](https://img.shields.io/badge/OpenWrt-19.07%20--%2025.x%2B-blue.svg)](https://openwrt.org)
[![Platform](https://img.shields.io/badge/Architecture-Universal%20(ARM%20%7C%20MIPS%20%7C%20x86)-orange.svg)]()
[![Interface](https://img.shields.io/badge/LuCI-Modern%20JS%20Web%20UI-green.svg)]()
[![Language](https://img.shields.io/badge/Language-Lua%20%7C%20Shell%20%7C%20JS-yellow.svg)]()

[**فارسی (Persian Documentation)**](README.fa.md)

---

## 🌟 Key Features

- 🖥️ **Modern LuCI Web UI:** Interactive dashboard in OpenWrt LuCI (`Services -> PassWall Sentinel`) displaying live status cards, complete node benchmark rankings table, and 50 direct DNS provider assessment tables.
- 🔒 **100% Direct Isolated Traffic:** Benchmarks nodes and 50 DNS providers directly over physical WAN (using firewall socket mark 255), with **zero routing through active proxies or VPNs**.
- 🛡️ **Armed Rollback & Anti-Brick Protection:** Every configuration change is protected with an automatic 60-second health check. If internet fails, it **automatically rolls back** to the last working state.
- 🚨 **Emergency Bypass Watchdog:** If PassWall freezes, crashes, or suffers a complete blackout, the watchdog automatically disables the proxy in seconds to preserve direct internet access.
- 🧠 **Hardware-Aware Scoring:** Penalizes CPU-heavy protocols (gRPC, QUIC) on low-power ARMv7/MIPS routers while boosting lightweight protocols (VLESS-Reality, ChaCha20).
- ⚡ **50 Curated DNS Benchmark:** Tests 50 international Anycast, privacy, and domestic anti-sanction DNS servers across UDP 53, TCP 53, and DoH 443 with fake IP (DNS poisoning) detection.
- ⚙️ **Manual vs Auto-Apply:** Choose whether to review recommendations before applying, or let the daemon seamlessly auto-select the best node.
- 📦 **Universal Compatibility:** Works out-of-the-box on modern OpenWrt 25.x (`apk`) and legacy OpenWrt (`opkg`) without compilation.

---

## 🚀 Quick Install (Single-Command)

Connect to your OpenWrt router via SSH and run:

```sh
curl -sSL https://raw.githubusercontent.com/mortezabahmani/passwall-sentinel/main/install.sh | sh
```

*(If using a private repository, clone via SSH and run locally):*

```sh
git clone git@github.com:mortezabahmani/passwall-sentinel.git
cd passwall-sentinel
sh install.sh
```

---

## 🖥️ Web User Interface (LuCI)

Navigate to **Services ➔ PassWall Sentinel** in your OpenWrt web interface:
* Direct URL: `http://192.168.1.1/cgi-bin/luci/admin/services/pwsentinel`

From the Web UI, you can:
1. View live status cards for active nodes, remote DoH, and benchmark recommendations.
2. Click **⚡ Run Benchmark Now** to execute live testing and view real-time table rankings.
3. Click **✅ Apply Recommendation** to safely apply winning settings with armed rollback.
4. Click **⏪ Rollback Snapshot** to revert changes.
5. Configure automated scheduling intervals.

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

## ⚙️ Configuration (`/etc/config/pwsentinel`)

```uci
config settings 'main'
    option enabled '1'                     # 1: Enable Sentinel background service
    option auto_apply '0'                  # 0: Manual approval | 1: Automatic apply
    option check_interval '6h'             # Schedule: 1h, 2h, 6h, 12h, 1d, 1w
    option max_nodes_to_test '5'           # Top candidate nodes to test deeply
    option failsafe_enabled '1'            # Emergency bypass watchdog
    option failsafe_loss_threshold '3'     # Failures before emergency bypass
    option bypass_mark '255'               # Socket mark for direct WAN traffic
```

---

## 📄 License
MIT License. Free for personal and community use.
Contribute and share with the OpenWrt anti-censorship community!
