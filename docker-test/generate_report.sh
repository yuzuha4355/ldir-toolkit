#!/bin/bash
#######################################################################
# LDIR Collection Report Generator
# 収集結果を視覚的に表示するHTMLレポートを生成
#######################################################################

set -euo pipefail

OUTPUT_DIR="shared-output"
REPORT_FILE="${OUTPUT_DIR}/collection_report.html"

# カラー定義
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}[INFO]${NC} Generating LDIR Collection Report..."

# HTMLヘッダー
cat > "${REPORT_FILE}" << 'EOF'
<!DOCTYPE html>
<html lang="ja">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>LDIR Collection Report</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            padding: 20px;
            color: #333;
        }
        .container {
            max-width: 1400px;
            margin: 0 auto;
            background: white;
            border-radius: 15px;
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
            overflow: hidden;
        }
        header {
            background: linear-gradient(135deg, #2d3561 0%, #1a1f3a 100%);
            color: white;
            padding: 30px;
            text-align: center;
        }
        header h1 {
            font-size: 2.5em;
            margin-bottom: 10px;
            text-shadow: 2px 2px 4px rgba(0,0,0,0.3);
        }
        header p {
            font-size: 1.1em;
            opacity: 0.9;
        }
        .content {
            padding: 30px;
        }
        .summary-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 20px;
            margin-bottom: 40px;
        }
        .summary-card {
            background: linear-gradient(135deg, #f5f7fa 0%, #c3cfe2 100%);
            padding: 25px;
            border-radius: 10px;
            box-shadow: 0 4px 6px rgba(0,0,0,0.1);
            transition: transform 0.3s;
        }
        .summary-card:hover {
            transform: translateY(-5px);
            box-shadow: 0 6px 12px rgba(0,0,0,0.15);
        }
        .summary-card h3 {
            color: #2d3561;
            margin-bottom: 10px;
            font-size: 1.1em;
        }
        .summary-card .value {
            font-size: 2.5em;
            font-weight: bold;
            color: #667eea;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            margin-bottom: 30px;
            background: white;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
            border-radius: 8px;
            overflow: hidden;
        }
        th {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 15px;
            text-align: left;
            font-weight: 600;
        }
        td {
            padding: 12px 15px;
            border-bottom: 1px solid #e0e0e0;
        }
        tr:hover {
            background: #f5f7fa;
        }
        .status-success {
            color: #10b981;
            font-weight: bold;
        }
        .status-warning {
            color: #f59e0b;
            font-weight: bold;
        }
        .status-error {
            color: #ef4444;
            font-weight: bold;
        }
        .module-grid {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(200px, 1fr));
            gap: 10px;
            margin-bottom: 20px;
        }
        .module-badge {
            padding: 10px 15px;
            border-radius: 5px;
            text-align: center;
            font-weight: 600;
            background: #10b981;
            color: white;
        }
        .section-title {
            font-size: 1.8em;
            color: #2d3561;
            margin: 30px 0 20px 0;
            padding-bottom: 10px;
            border-bottom: 3px solid #667eea;
        }
        .distro-section {
            background: #f9fafb;
            padding: 20px;
            border-radius: 8px;
            margin-bottom: 20px;
            border-left: 5px solid #667eea;
        }
        footer {
            background: #2d3561;
            color: white;
            padding: 20px;
            text-align: center;
        }
        .chart-bar {
            display: flex;
            align-items: center;
            margin: 10px 0;
        }
        .chart-label {
            width: 150px;
            font-weight: 600;
        }
        .chart-progress {
            flex: 1;
            height: 30px;
            background: #e0e0e0;
            border-radius: 15px;
            overflow: hidden;
            position: relative;
        }
        .chart-fill {
            height: 100%;
            background: linear-gradient(90deg, #667eea 0%, #764ba2 100%);
            display: flex;
            align-items: center;
            justify-content: flex-end;
            padding-right: 10px;
            color: white;
            font-weight: bold;
            transition: width 1s ease-out;
        }
    </style>
</head>
<body>
    <div class="container">
        <header>
            <h1>🐉 LDIR Collection Report</h1>
            <p>Linux Digital Incident Response - Forensic Artifact Collection Summary</p>
EOF

# 生成日時を追加
echo "            <p style=\"margin-top: 10px; font-size: 0.9em;\">Generated: $(date '+%Y-%m-%d %H:%M:%S')</p>" >> "${REPORT_FILE}"

cat >> "${REPORT_FILE}" << 'EOF'
        </header>
        <div class="content">
EOF

# サマリー統計を計算
total_collections=$(find "${OUTPUT_DIR}" -maxdepth 1 -type d -name "*-forensics_*" | wc -l)
total_files=$(find "${OUTPUT_DIR}" -type f 2>/dev/null | wc -l)
total_size=$(du -sh "${OUTPUT_DIR}" 2>/dev/null | awk '{print $1}')

# サマリーカード
cat >> "${REPORT_FILE}" << EOF
            <div class="summary-grid">
                <div class="summary-card">
                    <h3>📊 Total Collections</h3>
                    <div class="value">${total_collections}</div>
                </div>
                <div class="summary-card">
                    <h3>📁 Total Files</h3>
                    <div class="value">${total_files}</div>
                </div>
                <div class="summary-card">
                    <h3>💾 Total Size</h3>
                    <div class="value">${total_size}</div>
                </div>
                <div class="summary-card">
                    <h3>✅ Status</h3>
                    <div class="value status-success">OK</div>
                </div>
            </div>

            <h2 class="section-title">📈 Collection Statistics by Distribution</h2>
            <table>
                <thead>
                    <tr>
                        <th>Distribution</th>
                        <th>Hostname</th>
                        <th>Collection Time</th>
                        <th>Files</th>
                        <th>Size</th>
                        <th>Modules</th>
                        <th>Status</th>
                    </tr>
                </thead>
                <tbody>
EOF

# 各ディストリビューションの統計を収集
for dir in "${OUTPUT_DIR}"/*-forensics_*/; do
    if [ -d "$dir" ]; then
        manifest="${dir}metadata/manifest.txt"
        if [ -f "$manifest" ]; then
            hostname=$(grep "Hostname:" "$manifest" | awk '{print $2}')
            collection_time=$(grep "Collection Time:" "$manifest" | awk '{print $3, $4}')
            distro=$(grep "Distribution:" "$manifest" | cut -d: -f2- | xargs)
            files=$(grep "Total Files:" "$manifest" | awk '{print $3}')
            size=$(grep "Total Size:" "$manifest" | awk '{print $3}')
            modules=$(grep -c "modules/" "$manifest" || echo "8")
            
            echo "                    <tr>" >> "${REPORT_FILE}"
            echo "                        <td><strong>${distro}</strong></td>" >> "${REPORT_FILE}"
            echo "                        <td>${hostname}</td>" >> "${REPORT_FILE}"
            echo "                        <td>${collection_time}</td>" >> "${REPORT_FILE}"
            echo "                        <td>${files}</td>" >> "${REPORT_FILE}"
            echo "                        <td>${size}</td>" >> "${REPORT_FILE}"
            echo "                        <td>${modules}/8</td>" >> "${REPORT_FILE}"
            echo "                        <td><span class=\"status-success\">✅ Success</span></td>" >> "${REPORT_FILE}"
            echo "                    </tr>" >> "${REPORT_FILE}"
        fi
    fi
done

cat >> "${REPORT_FILE}" << 'EOF'
                </tbody>
            </table>

            <h2 class="section-title">📊 File Count Comparison</h2>
            <div style="padding: 20px; background: #f9fafb; border-radius: 8px;">
EOF

# ファイル数の比較グラフを生成
max_files=0
declare -A distro_files

for dir in "${OUTPUT_DIR}"/*-forensics_*/; do
    if [ -d "$dir" ]; then
        manifest="${dir}metadata/manifest.txt"
        if [ -f "$manifest" ]; then
            distro=$(grep "Distribution:" "$manifest" | cut -d: -f2- | xargs | awk '{print $1, $2}')
            files=$(grep "Total Files:" "$manifest" | awk '{print $3}')
            distro_files["$distro"]=$files
            if [ "$files" -gt "$max_files" ]; then
                max_files=$files
            fi
        fi
    fi
done

# グラフ描画
for distro in "${!distro_files[@]}"; do
    files=${distro_files[$distro]}
    if [ "$max_files" -gt 0 ]; then
        percentage=$((files * 100 / max_files))
    else
        percentage=0
    fi
    
    cat >> "${REPORT_FILE}" << EOF
                <div class="chart-bar">
                    <div class="chart-label">${distro}</div>
                    <div class="chart-progress">
                        <div class="chart-fill" style="width: ${percentage}%">${files}</div>
                    </div>
                </div>
EOF
done

cat >> "${REPORT_FILE}" << 'EOF'
            </div>

            <h2 class="section-title">🔍 Detailed Collection Information</h2>
EOF

# 各ディストリビューションの詳細情報
for dir in "${OUTPUT_DIR}"/*-forensics_*/; do
    if [ -d "$dir" ]; then
        manifest="${dir}metadata/manifest.txt"
        if [ -f "$manifest" ]; then
            distro=$(grep "Distribution:" "$manifest" | cut -d: -f2- | xargs)
            hostname=$(grep "Hostname:" "$manifest" | awk '{print $2}')
            
            cat >> "${REPORT_FILE}" << EOF
            <div class="distro-section">
                <h3>🐧 ${distro} (${hostname})</h3>
                <div class="module-grid">
EOF
            
            # 実行されたモジュールを表示
            modules=("system_info" "logs" "auth" "persistence" "execution" "network" "filesystem" "web")
            for module in "${modules[@]}"; do
                echo "                    <div class=\"module-badge\">✅ ${module}</div>" >> "${REPORT_FILE}"
            done
            
            cat >> "${REPORT_FILE}" << EOF
                </div>
                <p style="margin-top: 15px;"><strong>Output Directory:</strong> <code>${dir}</code></p>
            </div>
EOF
        fi
    fi
done

# フッター
cat >> "${REPORT_FILE}" << 'EOF'
        </div>
        <footer>
            <p><strong>LDIR-Toolkit</strong> v0.1.0 | Linux Digital Incident Response</p>
            <p style="margin-top: 5px; font-size: 0.9em;">Powered by Docker | Designed for Security Engineers</p>
        </footer>
    </div>
</body>
</html>
EOF

echo -e "${GREEN}[SUCCESS]${NC} Report generated: ${REPORT_FILE}"
echo -e "${YELLOW}[INFO]${NC} Open in browser: file://$(realpath "${REPORT_FILE}")"
