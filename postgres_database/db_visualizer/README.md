# Simple DB Viewer (Optional)

This is an optional helper Node.js app to quickly inspect databases (PostgreSQL, MySQL, SQLite, MongoDB) from this container.

Auto-start: Disabled by default to prevent container failures if Node dependencies are not installed.
- To enable auto-start on container boot, set environment variable: DB_VIEWER=1
- Without DB_VIEWER=1, the viewer will NOT be started automatically.

How to run manually:
1. cd db_visualizer
2. npm install --no-audit --no-fund --silent
3. source ./postgres.env   # or the respective env file for your DB
4. npm start

Default host/port: http://0.0.0.0:3000 (accessible on localhost if port mapped)
