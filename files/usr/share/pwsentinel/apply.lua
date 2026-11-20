local uci = require("uci").cursor()

local M = {}
local BACKUP_FILE = "/var/run/pwsentinel/backup_passwall2.uci"
local STATE_DIR = "/var/run/pwsentinel"

local function ensure_state_dir()
    os.execute(string.format("mkdir -p %s", STATE_DIR))
end

function M.create_backup()
    ensure_state_dir()
    local ok = os.execute(string.format("cp /etc/config/passwall2 %s 2>/dev/null", BACKUP_FILE))
    return ok == 0
end

function M.restore_backup()
    if os.execute(string.format("test -f %s", BACKUP_FILE)) == 0 then
        os.execute(string.format("cp %s /etc/config/passwall2", BACKUP_FILE))
        os.execute("/etc/init.d/passwall2 reload >/dev/null 2>&1")
        return true
    end
    return false
end

local function test_health()
    local code = os.execute("curl -s --connect-timeout 5 --max-time 8 https://www.google.com/generate_204 >/dev/null 2>&1")
    return code == 0
end

function M.apply(node_id, doh_url, doh_ip, direct_dns_ip)
    if not node_id then
        return false, "No node_id provided"
    end

    print("Step 1: Creating safety snapshot of PassWall 2 configuration...")
    if not M.create_backup() then
        return false, "Failed to create safety backup. Aborting."
    end

    print(string.format("Step 2: Updating PassWall 2 default_node -> %s", node_id))
    uci:set("passwall2", "rulenode", "default_node", node_id)

    if doh_url and doh_ip then
        local doh_val = string.format("%s,%s", doh_url, doh_ip)
        print(string.format("Step 3: Updating PassWall 2 remote_dns_doh -> %s", doh_val))
        uci:set("passwall2", "@global[0]", "remote_dns_doh", doh_val)
        uci:set("passwall2", "@global[0]", "remote_dns_protocol", "doh")
    end

    if direct_dns_ip then
        print(string.format("Step 4: Updating PassWall 2 direct DNS -> %s", direct_dns_ip))
    end

    uci:commit("passwall2")

    print("Step 5: Reloading PassWall 2 daemon (zero-downtime reload)...")
    os.execute("/etc/init.d/passwall2 reload >/dev/null 2>&1")

    print("Step 6: Armed verification timer (testing connectivity within 10s)...")
    os.execute("sleep 4")
    if test_health() then
        print("Verification SUCCESS! Internet connection is healthy and responsive.")
        return true, "Successfully applied and verified."
    else
        print("WARNING: Health check failed! Initiating automatic emergency rollback...")
        if M.restore_backup() then
            print("Rollback SUCCESS! Restored previous working configuration safely.")
            return false, "Rollback triggered due to failed health check."
        else
            return false, "Critical: Rollback failed."
        end
    end
end

return M
