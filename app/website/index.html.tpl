<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>CloudGuard Dashboard</title>
<style>
  body { font-family: Arial, sans-serif; background: #0b1220; color: #e6edf3; margin: 0; padding: 2rem; }
  h1 { color: #58a6ff; }
  table { width: 100%; border-collapse: collapse; margin-top: 1.5rem; }
  th, td { text-align: left; padding: 0.6rem; border-bottom: 1px solid #30363d; font-size: 0.9rem; }
  th { color: #8b949e; text-transform: uppercase; font-size: 0.75rem; }
  .risk-high_risk { color: #f85149; font-weight: bold; }
  .risk-low_risk { color: #3fb950; font-weight: bold; }
  .status { padding: 2px 8px; border-radius: 4px; font-size: 0.75rem; background: #21262d; }
  #loading { color: #8b949e; margin-top: 1rem; }
</style>
</head>
<body>
  <h1>CloudGuard — Drift Detection Audit Log</h1>
  <p id="loading">Loading findings...</p>
  <table id="findingsTable" style="display:none;">
    <thead>
      <tr>
        <th>Timestamp</th>
        <th>Resource</th>
        <th>Field</th>
        <th>Desired</th>
        <th>Live</th>
        <th>Risk</th>
        <th>Status</th>
        <th>Action Taken</th>
      </tr>
    </thead>
    <tbody id="findingsBody"></tbody>
  </table>

  <script>
    const API_URL = "${api_url}/findings";

    fetch(API_URL)
      .then(res => res.json())
      .then(data => {
        const body = document.getElementById("findingsBody");
        const findings = data.findings || [];

        if (findings.length === 0) {
          document.getElementById("loading").textContent = "No drift findings yet.";
          return;
        }

        findings.forEach(f => {
          const row = document.createElement("tr");
          row.innerHTML = `
            <td>$${f.timestamp || ""}</td>
            <td>$${f.resource || ""}</td>
            <td>$${f.field || ""}</td>
            <td>$${f.desired_value || ""}</td>
            <td>$${f.live_value || ""}</td>
            <td class="risk-$${f.risk_tier}">$${f.risk_tier || ""}</td>
            <td><span class="status">$${f.status || ""}</span></td>
            <td>$${f.action_taken || ""}</td>
          `;
          body.appendChild(row);
        });

        document.getElementById("loading").style.display = "none";
        document.getElementById("findingsTable").style.display = "table";
      })
      .catch(err => {
        document.getElementById("loading").textContent = "Error loading findings: " + err;
      });
  </script>
</body>
</html>
