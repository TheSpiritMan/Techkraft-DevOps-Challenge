- Command: 
  ```sh
  bash analyze_nginx_logs.sh /var/log/nginx/access.log.1
  ```
  Output:
  ```sh
  ╔══════════════════════════════════════════════════════════╗
  ║          Nginx Log Analysis Report                       ║
  ╚══════════════════════════════════════════════════════════╝
  
  Log file     : /var/log/nginx/access.log.1
  Analyzed at  : 2026-05-02 07:49:13 UTC
  Total lines  : 135 (skipped 0 malformed)
  ────────────────────────────────────────────────────────────
  Total Requests:                135
  Unique IPs:                    70
  4xx Errors:                    14 (10.37%)
  5xx Errors:                    0 (0.00%)
  ────────────────────────────────────────────────────────────
  
  Top 10 IP Addresses:
  ────────────────────────────────────────────────────────────
    Rank  IP Address           Requests
    ──── ────────── ────────
    1.    3.129.<X>.<Y>         10
    2.    3.130.<X>.<Y>          9
    3.    89.42.<X>.<Y>          8
    4.    185.242.<X>.<Y>        6
    5.    66.132.<X>.<Y>         5
    6.    167.94.<X>.<Y>         5
    7.    93.174.<X>.<Y>         4
    8.    46.161.<X>.<Y>         4
    9.    43.106.<X>.<Y>         4
    10.   3.131.<X>.<Y>          4
  
  Top 10 Endpoints:
  ────────────────────────────────────────────────────────────
    Rank  Endpoint                                      Requests
    ──── ────────                      ────────
    1.    /                                             59
    2.    /favicon.ico                                  3
    3.    /icon.png?a5684e96c18df834                    2
    4.    /?XDEBUG_SESSION_START=phpstorm               1
    5.    /wiki                                         1
    6.    /.well-known/security.txt                     1
    7.    /webui/                                       1
    8.    /SDK/webLanguage                              1
    9.    /portal/redlion                               1
    10.   /Mt4g                                         1
  
  HTTP Status Code Breakdown:
  ────────────────────────────────────────────────────────────
    Status     Count
    ────── ─────
    301        81
    157        14
    405        8
    400        6
  ────────────────────────────────────────────────────────────
  Analysis complete.
  ```