'use strict';
'require view';
'require form';
'require uci';
'require ui';
'require fs';

return view.extend({
	load: function() {
		return Promise.all([
			uci.load('pwsentinel'),
			uci.load('passwall2'),
			fs.read('/var/run/pwsentinel/latest_benchmark.json').catch(function() {
				return fs.read('/tmp/run/pwsentinel/latest_benchmark.json');
			}).then(function(content) {
				try {
					return JSON.parse(content);
				} catch(e) {
					return null;
				}
			}).catch(function() {
				return null;
			})
		]);
	},

	render: function(data) {
		var m, s, o;
		var bench_data = data[2] || null;

		// 1. Fetch current status
		var current_node_id = uci.get('passwall2', 'rulenode', 'default_node') || 'None';
		var current_node_name = 'Unknown';
		if (current_node_id !== 'None') {
			current_node_name = uci.get('passwall2', current_node_id, 'remarks') || current_node_id;
		}
		var current_doh = uci.get('passwall2', '@global[0]', 'remote_dns_doh') || 'None';

		var best_node_id = uci.get('pwsentinel', 'main', 'best_node_id') || 'None';
		var best_node_name = uci.get('pwsentinel', 'main', 'best_node_name') || 'None';
		var best_doh = uci.get('pwsentinel', 'main', 'best_doh_url') || 'None';
		var best_direct = uci.get('pwsentinel', 'main', 'best_direct_dns') || 'None';
		var last_run = uci.get('pwsentinel', 'main', 'last_run_time') || 'Never';
		var auto_apply = uci.get('pwsentinel', 'main', 'auto_apply') === '1';

		m = new form.Map('pwsentinel', _('PassWall Sentinel'),
			_('Intelligent Failsafe Watchdog & Isolated Benchmark Engine for PassWall 2. Benchmarks nodes and 50 DNS providers via 100% direct WAN traffic without passing through active proxies.'));

		s = m.section(form.NamedSection, 'main', 'settings');
		s.anonymous = true;

		// Tabs
		s.tab('dashboard', _('Dashboard & Live Results'));
		s.tab('general', _('General Settings'));
		s.tab('failsafe', _('Failsafe & Anti-Brick'));

		// --- TAB 1: DASHBOARD ---
		o = s.taboption('dashboard', form.DummyValue, '_status_dashboard');
		o.rawhtml = true;
		o.cfgvalue = function() {
			var badge_auto = auto_apply ?
				'<span class="badge" style="background:#28a745;color:#fff;padding:3px 8px;border-radius:4px;font-size:0.85em;">Automatic</span>' :
				'<span class="badge" style="background:#ffc107;color:#000;padding:3px 8px;border-radius:4px;font-size:0.85em;">Manual Approval</span>';

			return '<div style="background:#f8f9fa; border:1px solid #e9ecef; border-radius:8px; padding:16px; margin-bottom:16px;">' +
				'<div style="display:grid; grid-template-columns: repeat(auto-fit, minmax(240px, 1fr)); gap:16px;">' +
					'<div>' +
						'<strong>Active PassWall 2 Node:</strong><br>' +
						'<span style="font-size:1.1em; color:#007bff; font-weight:bold;">' + current_node_name + '</span><br>' +
						'<small style="color:#6c757d;">ID: ' + current_node_id + '</small>' +
					'</div>' +
					'<div>' +
						'<strong>Active Remote DoH DNS:</strong><br>' +
						'<span style="font-size:1.0em; color:#17a2b8; font-weight:bold;">' + current_doh + '</span><br>' +
						'<small style="color:#6c757d;">Protection Mode: ' + badge_auto + '</small>' +
					'</div>' +
					'<div>' +
						'<strong>Latest Benchmark Winner:</strong><br>' +
						'<span style="font-size:1.1em; color:#28a745; font-weight:bold;">' + best_node_name + '</span><br>' +
						'<small style="color:#6c757d;">Proposed DoH: ' + best_doh + '</small>' +
					'</div>' +
					'<div>' +
						'<strong>Last Check Time:</strong><br>' +
						'<span style="font-size:1.0em; color:#495057;">' + last_run + '</span><br>' +
						'<small style="color:#6c757d;">Direct Domestic DNS: ' + best_direct + '</small>' +
					'</div>' +
				'</div>' +
			'</div>';
		};

		// Action Buttons
		o = s.taboption('dashboard', form.DummyValue, '_actions');
		o.rawhtml = true;
		o.cfgvalue = function() {
			return '<div style="display:flex; gap:10px; margin-bottom:20px; flex-wrap:wrap;">' +
				'<button class="cbi-button cbi-button-apply" id="btn-run-bench" style="font-weight:bold;">⚡ Run Benchmark Now</button>' +
				'<button class="cbi-button cbi-button-save" id="btn-apply-rec" style="font-weight:bold;">✅ Apply Recommendation</button>' +
				'<button class="cbi-button cbi-button-reset" id="btn-rollback" style="font-weight:bold;">⏪ Rollback Snapshot</button>' +
			'</div>';
		};

		// Detailed Benchmark Results Display (Tables)
		o = s.taboption('dashboard', form.DummyValue, '_bench_results');
		o.rawhtml = true;
		o.cfgvalue = function() {
			if (!bench_data) {
				return '<div class="alert-message warning">' +
					_('No benchmark results found yet. Click <strong>"Run Benchmark Now"</strong> to audit all nodes and 50 direct DNS servers.') +
					'</div>';
			}

			var html = '<div style="margin-top:20px;">';

			// --- TABLE 1: TOP 5 NODE BENCHMARK RANKINGS ---
			html += '<h3>🏆 Top Candidate Nodes Ranking (Tested 100% via Direct WAN)</h3>';
			html += '<div class="table" style="width:100%; overflow-x:auto;">' +
				'<table class="table cbi-section-table" style="width:100%;">' +
				'<tr class="tr cbi-section-table-titles">' +
					'<th class="th">Rank</th>' +
					'<th class="th">Node Remarks</th>' +
					'<th class="th">Protocol / Transport</th>' +
					'<th class="th">Direct TCP Ping</th>' +
					'<th class="th">TTFB (Real Bypass)</th>' +
					'<th class="th">Hardware Score</th>' +
					'<th class="th">Status</th>' +
				'</tr>';

			var nodes = bench_data.nodes || [];
			if (nodes.length === 0) {
				html += '<tr class="tr"><td class="td" colspan="7">No active candidate nodes recorded.</td></tr>';
			} else {
				for (var i = 0; i < Math.min(5, nodes.length); i++) {
					var n = nodes[i];
					var is_best = (i === 0 && n.status === 'OK');
					var row_style = is_best ? 'background:rgba(40,167,69,0.12); font-weight:bold;' : '';
					var badge = is_best ? '<span class="badge" style="background:#28a745;color:#fff;padding:2px 8px;border-radius:4px;font-weight:bold;">🏆 Winner #1</span>' : '<span class="badge" style="background:#6c757d;color:#fff;padding:2px 6px;border-radius:4px;">#' + (i + 1) + '</span>';

					html += '<tr class="tr cbi-section-table-row" style="' + row_style + '">' +
						'<td class="td">' + badge + '</td>' +
						'<td class="td"><strong>' + (n.remarks || 'Unknown') + '</strong><br><small style="color:#888;">ID: ' + n.id + '</small></td>' +
						'<td class="td">' + (n.protocol || '-') + ' / ' + (n.transport || 'raw') + '</td>' +
						'<td class="td">' + (typeof(n.tcp_rtt) === 'number' ? n.tcp_rtt.toFixed(1) + ' ms' : 'N/A') + '</td>' +
						'<td class="td">' + (typeof(n.ttfb) === 'number' ? n.ttfb.toFixed(1) + ' ms' : (n.ttfb || 'N/A')) + '</td>' +
						'<td class="td">' + (typeof(n.score) === 'number' ? n.score.toFixed(1) : 'N/A') + '</td>' +
						'<td class="td">' + (n.status === 'OK' ? '<span style="color:#28a745;font-weight:bold;">✔ OK</span>' : '<span style="color:#dc3545;font-weight:bold;">✖ ' + n.status + '</span>') + '</td>' +
					'</tr>';
				}
			}
			html += '</table></div><br><br>';

			// Process DNS Providers
			var dns_list = bench_data.dns || [];
			var foreign_dns = [];
			var domestic_dns = [];

			var best_doh_item = bench_data.best_doh || null;
			var best_tcp_item = bench_data.best_tcp || null;
			var best_udp_item = bench_data.best_udp || null;
			var best_domestic_item = bench_data.best_domestic || null;

			for (var k = 0; k < dns_list.length; k++) {
				var item = dns_list[k];
				if (item.type === 'domestic') {
					domestic_dns.push(item);
					if (item.udp_status === 'OK' && typeof(item.udp_time) === 'number') {
						if (!best_domestic_item || item.udp_time < (best_domestic_item.udp_time || 9999)) {
							best_domestic_item = item;
						}
					}
				} else {
					foreign_dns.push(item);
				}

				if (item.doh_status === 'OK' && typeof(item.doh_time) === 'number') {
					if (!best_doh_item || item.doh_time < (best_doh_item.doh_time || 9999)) {
						best_doh_item = item;
					}
				}
				if (item.tcp_status === 'OK' && typeof(item.tcp_time) === 'number') {
					if (!best_tcp_item || item.tcp_time < (best_tcp_item.tcp_time || 9999)) {
						best_tcp_item = item;
					}
				}
				if (item.udp_status === 'OK' && typeof(item.udp_time) === 'number') {
					if (!best_udp_item || item.udp_time < (best_udp_item.udp_time || 9999)) {
						best_udp_item = item;
					}
				}
			}

			function renderDnsRow(d) {
				var is_best_doh = (best_doh_item && best_doh_item.ip === d.ip);
				var is_best_tcp = (best_tcp_item && best_tcp_item.ip === d.ip);
				var is_best_udp = (best_udp_item && best_udp_item.ip === d.ip);
				var is_best_dom = (best_domestic_item && best_domestic_item.ip === d.ip);

				var d_style = '';
				var badges = [];

				if (is_best_doh) {
					d_style = 'background:rgba(23,162,184,0.12); font-weight:bold;';
					badges.push('<span class="badge" style="background:#17a2b8;color:#fff;padding:2px 6px;border-radius:4px;margin-right:4px;">🛡️ Best DoH</span>');
				}
				if (is_best_tcp) {
					d_style = d_style || 'background:rgba(111,66,193,0.1); font-weight:bold;';
					badges.push('<span class="badge" style="background:#6f42c1;color:#fff;padding:2px 6px;border-radius:4px;margin-right:4px;">🚀 Best TCP</span>');
				}
				if (is_best_udp) {
					d_style = d_style || 'background:rgba(40,167,69,0.1); font-weight:bold;';
					badges.push('<span class="badge" style="background:#28a745;color:#fff;padding:2px 6px;border-radius:4px;margin-right:4px;">⚡ Best UDP</span>');
				}
				if (is_best_dom) {
					d_style = 'background:rgba(0,123,255,0.12); font-weight:bold;';
					badges.push('<span class="badge" style="background:#007bff;color:#fff;padding:2px 6px;border-radius:4px;margin-right:4px;">🇮🇷 Best Domestic</span>');
				}

				if (d.udp_status === 'POISONED') {
					badges.push('<span class="badge" style="background:#dc3545;color:#fff;padding:2px 6px;border-radius:4px;">🚫 Censored / Poisoned</span>');
				} else if (badges.length === 0) {
					if (d.udp_status === 'OK' || d.tcp_status === 'OK' || d.doh_status === 'OK') {
						badges.push('<span style="color:#28a745;">Clean & Reachable</span>');
					} else {
						badges.push('<span style="color:#6c757d;">Unreachable</span>');
					}
				}

				var udp_str = '-';
				if (d.udp_status === 'POISONED') {
					udp_str = '<span style="color:#dc3545;font-weight:bold;">POISONED (188.114.98.0)</span>';
				} else if (d.udp_status === 'OK' && typeof(d.udp_time) === 'number') {
					udp_str = '<span style="color:#28a745;">' + d.udp_time.toFixed(1) + ' ms</span>';
				} else {
					udp_str = '<span style="color:#6c757d;">' + (d.udp_status || 'TIMEOUT') + '</span>';
				}

				var tcp_str = d.tcp_status === 'OK' && typeof(d.tcp_time) === 'number' ? d.tcp_time.toFixed(1) + ' ms' : '<span style="color:#6c757d;">' + (d.tcp_status || 'FAIL') + '</span>';
				var doh_str = d.doh_status === 'OK' && typeof(d.doh_time) === 'number' ? '<span style="color:#17a2b8;">' + d.doh_time.toFixed(1) + ' ms</span>' : '<span style="color:#6c757d;">' + (d.doh_status || 'N/A') + '</span>';

				return '<tr class="tr cbi-section-table-row" style="' + d_style + '">' +
					'<td class="td"><strong>' + d.name + '</strong></td>' +
					'<td class="td"><code>' + d.ip + '</code></td>' +
					'<td class="td">' + udp_str + '</td>' +
					'<td class="td">' + tcp_str + '</td>' +
					'<td class="td">' + doh_str + '</td>' +
					'<td class="td">' + badges.join(' ') + '</td>' +
				'</tr>';
			}

			// --- TABLE 2: FOREIGN & INTERNATIONAL DNS (DIRECT WAN) ---
			html += '<h3>🛡️ Foreign & International DNS Providers (Direct WAN Audit)</h3>';
			html += '<p style="color:#6c757d;margin-bottom:8px;">Evaluates direct UDP 53 poisoning, TCP 53 fallback, and secure DoH 443 resolution against censorship firewalls.</p>';
			html += '<div class="table" style="width:100%; max-height:420px; overflow-y:auto; overflow-x:auto;">' +
				'<table class="table cbi-section-table" style="width:100%;">' +
				'<tr class="tr cbi-section-table-titles" style="position:sticky; top:0; background:#f0f0f0; z-index:2;">' +
					'<th class="th">Provider Name</th>' +
					'<th class="th">IP Address</th>' +
					'<th class="th">UDP 53 (Direct)</th>' +
					'<th class="th">TCP 53 (Direct)</th>' +
					'<th class="th">DoH 443 (Direct)</th>' +
					'<th class="th">Assessment & Best Category</th>' +
				'</tr>';

			for (var j = 0; j < foreign_dns.length; j++) {
				html += renderDnsRow(foreign_dns[j]);
			}
			html += '</table></div><br><br>';

			// --- TABLE 3: IRANIAN DOMESTIC & ANTI-SANCTION RESOLVERS ---
			html += '<h3>🇮🇷 Domestic Iranian & Anti-Sanction DNS Providers (سامانه‌های تحریم‌شکن و داخلی)</h3>';
			html += '<p style="color:#6c757d;margin-bottom:8px;">Domestic anti-sanction services (Shecan, Electro, Radar Game, 403.online, Begzar) bypass foreign 403 sanctions without proxying overhead.</p>';
			html += '<div class="table" style="width:100%; overflow-x:auto;">' +
				'<table class="table cbi-section-table" style="width:100%;">' +
				'<tr class="tr cbi-section-table-titles" style="background:#e8f4f8;">' +
					'<th class="th">Domestic Resolver</th>' +
					'<th class="th">IP Address</th>' +
					'<th class="th">UDP 53 (Direct)</th>' +
					'<th class="th">TCP 53 (Direct)</th>' +
					'<th class="th">DoH 443 (Direct)</th>' +
					'<th class="th">Assessment & Best Category</th>' +
				'</tr>';

			for (var m_idx = 0; m_idx < domestic_dns.length; m_idx++) {
				html += renderDnsRow(domestic_dns[m_idx]);
			}
			html += '</table></div></div>';

			return html;
		};

		// --- TAB 2: GENERAL SETTINGS ---
		o = s.taboption('general', form.Flag, 'enabled', _('Enable Sentinel'), _('Enable the background scheduling and watchdog daemon'));
		o.default = '1';
		o.rmempty = false;

		o = s.taboption('general', form.Flag, 'auto_apply', _('Auto-Apply Winners'), _('Automatically update PassWall 2 default_node and DNS without manual approval'));
		o.default = '0';
		o.rmempty = false;

		o = s.taboption('general', form.ListValue, 'check_interval', _('Benchmark Interval'), _('How often Sentinel should automatically run the isolated benchmark'));
		o.value('1h', _('Every 1 Hour'));
		o.value('2h', _('Every 2 Hours'));
		o.value('6h', _('Every 6 Hours (Recommended)'));
		o.value('12h', _('Every 12 Hours'));
		o.value('1d', _('Once Daily (04:00 AM)'));
		o.value('1w', _('Once Weekly (Sunday 04:00 AM)'));
		o.default = '6h';

		o = s.taboption('general', form.Value, 'max_nodes_to_test', _('Max Candidate Nodes'), _('Number of lowest-latency nodes to test deeply via ephemeral port (guards CPU)'));
		o.datatype = 'uinteger';
		o.default = '5';

		// --- TAB 3: FAILSAFE & ANTI-BRICK ---
		o = s.taboption('failsafe', form.Flag, 'failsafe_enabled', _('Emergency Watchdog'), _('Automatically bypasses PassWall 2 if total connection loss is detected, preventing lockouts'));
		o.default = '1';
		o.rmempty = false;

		o = s.taboption('failsafe', form.Value, 'failsafe_loss_threshold', _('Failure Threshold'), _('Number of consecutive failed health checks before engaging emergency direct bypass'));
		o.datatype = 'uinteger';
		o.default = '3';

		o = s.taboption('failsafe', form.Value, 'bypass_mark', _('Direct Socket Mark'), _('Firewall fwmark used to force 100% direct WAN routing'));
		o.datatype = 'uinteger';
		o.default = '255';

		o = s.taboption('failsafe', form.Value, 'direct_interface', _('Direct Interface'), _('Physical WAN interface used for direct benchmarking'));
		o.default = 'wan';

		// Attach Event Listeners to Buttons after render
		var view_node = m.render();
		view_node.then(function(node) {
			setTimeout(function() {
				var btnBench = document.getElementById('btn-run-bench');
				var btnApply = document.getElementById('btn-apply-rec');
				var btnRollback = document.getElementById('btn-rollback');

				if (btnBench) {
					btnBench.addEventListener('click', function(ev) {
						ev.preventDefault();
						var outputPre = E('pre', {
							'style': 'max-height:420px; overflow-y:auto; background:#181818; color:#38ef7d; padding:12px; border-radius:6px; font-size:0.85em; font-family:monospace; white-space:pre-wrap; margin-top:10px;'
						}, _('Initiating isolated direct WAN benchmark...\n'));

						ui.showModal(_('Running Isolated Benchmark...'), [
							E('p', { 'class': 'spinning' }, _('Benchmarking PassWall nodes and 50 direct DNS servers directly via WAN. Please wait...')),
							outputPre
						]);

						fs.exec_direct('/usr/bin/pwsentinel', ['check'], 'text', false, true, function(xhr) {
							if (xhr.responseText) {
								outputPre.textContent = xhr.responseText;
								outputPre.scrollTop = outputPre.scrollHeight;
							}
						}).then(function(res) {
							outputPre.textContent = res || _('Benchmark finished successfully.');
							outputPre.scrollTop = outputPre.scrollHeight;
							ui.showModal(_('Benchmark Finished'), [
								outputPre,
								E('div', { 'class': 'right', 'style': 'margin-top:12px;' }, [
									E('button', {
										'class': 'btn btn-primary',
										'click': function() { location.reload(); }
									}, _('Refresh View & Show Tables'))
								])
							]);
						}).catch(function(err) {
							ui.addNotification(null, E('p', _('Benchmark failed: ') + (err.message || err)), 'error');
							ui.hideModal();
						});
					});
				}

				if (btnApply) {
					btnApply.addEventListener('click', function(ev) {
						ev.preventDefault();
						var applyPre = E('pre', {
							'style': 'max-height:320px; overflow-y:auto; background:#181818; color:#38ef7d; padding:12px; border-radius:6px; font-size:0.85em; font-family:monospace; white-space:pre-wrap; margin-top:10px;'
						}, _('Initiating configuration apply with safety snapshot...\n'));

						ui.showModal(_('Applying Recommendation...'), [
							E('p', { 'class': 'spinning' }, _('Applying best node and DNS to PassWall 2 with 60-second armed rollback...')),
							applyPre
						]);

						fs.exec_direct('/usr/bin/pwsentinel', ['apply'], 'text', false, true, function(xhr) {
							if (xhr.responseText) {
								applyPre.textContent = xhr.responseText;
								applyPre.scrollTop = applyPre.scrollHeight;
							}
						}).then(function(res) {
							applyPre.textContent = res || _('Applied successfully.');
							applyPre.scrollTop = applyPre.scrollHeight;
							ui.showModal(_('Apply Finished'), [
								applyPre,
								E('div', { 'class': 'right', 'style': 'margin-top:12px;' }, [
									E('button', {
										'class': 'btn btn-primary',
										'click': function() { location.reload(); }
									}, _('Done & Refresh View'))
								])
							]);
						}).catch(function(err) {
							var msg = err.message || String(err);
							if (msg.indexOf('aborted') !== -1 || msg.indexOf('timed out') !== -1) {
								applyPre.textContent += '\n\n' + _('PassWall 2 reloaded its routing core. Network connection momentarily refreshed.\nVerifying router state and reloading page in 4 seconds...');
								setTimeout(function() {
									location.reload();
								}, 4000);
							} else {
								ui.addNotification(null, E('p', _('Apply failed: ') + msg), 'error');
								ui.hideModal();
							}
						});
					});
				}

				if (btnRollback) {
					btnRollback.addEventListener('click', function(ev) {
						ev.preventDefault();
						if (!confirm(_('Are you sure you want to rollback PassWall 2 to the previous safety snapshot?'))) return;
						fs.exec_direct('/usr/bin/pwsentinel', ['rollback'], 'text').then(function(res) {
							ui.addNotification(null, E('p', res || _('Rollback executed successfully.')), 'info');
							setTimeout(function() { location.reload(); }, 1500);
						}).catch(function(err) {
							ui.addNotification(null, E('p', _('Rollback failed: ') + (err.message || err)), 'error');
						});
					});
				}
			}, 300);
		});

		return view_node;
	},

	handleSaveApply: function(ev, mode) {
		return this.super('handleSaveApply', [ev, mode]).then(function() {
			fs.exec('/etc/init.d/pwsentinel', ['restart']);
		});
	}
});
