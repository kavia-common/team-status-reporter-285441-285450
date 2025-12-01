# Simple DB Viewer (Optional)

This is an optional helper Node.js app to quickly inspect databases (PostgreSQL, MySQL, SQLite, MongoDB) from this container.

Auto-start: Disabled by default to prevent container failures if Node dependencies are not installed.
- To enable auto-start on container boot, set environment variable: DB_VIEWER=1
- Without DB_VIEWER=1, the viewer will NOT be started automatically.
- The startup script includes a dependency check; if express is not installed after npm install, the viewer will be skipped with a warning.

How to run manually:
1. cd db_visualizer
2. npm install --no-audit --no-fund --silent
3. source ./postgres.env   # or the respective env file for your DB
4. npm start

Default host/port: http://0.0.0.0:3000 (accessible on localhost if port mapped)

Note:
- The database container never executes `npm start` or `node server.js` for this viewer unless DB_VIEWER=1 is set. When DB_VIEWER is not set to 1, `npm start` for this package intentionally exits with non-zero status to prevent accidental runs.
- If Node/npm are not present or dependencies fail to install, startup is skipped and the database continues to run normally.
