#!/usr/bin/env bash
# demo-steps.sh — Helper for VHS demo
# Usage: bash demo-steps.sh <step>
set -f
STEP="$1"
DB=$(find "$HOME/.copilot/session-state" -name "session.db" -newer "$HOME/.copilot/session-store.db" 2>/dev/null | head -1)
if [ -z "$DB" ]; then
  DB=$(ls -t "$HOME"/.copilot/session-state/*/session.db 2>/dev/null | head -1)
fi

case "$STEP" in
  init)
    sqlite3 "$DB" "DELETE FROM todos; DELETE FROM phases;"
    sqlite3 "$DB" "INSERT INTO phases VALUES('ph1','Setup',1,'in_progress'),('ph2','Build',2,'pending'),('ph3','Ship',3,'pending');"
    sqlite3 "$DB" "INSERT INTO todos(id,title,status) VALUES('ph1-t01','Scaffold','pending'),('ph1-t02','Config','pending'),('ph1-t03','Deps','pending');"
    sqlite3 "$DB" "INSERT OR REPLACE INTO session_state(key,value) VALUES('activity','Starting Phase 1: Setup'),('total_tasks','3'),('total_phases','3'),('phase_heading','Phase 1: Setup');"
    echo "Created 3 phases, 3 tasks"
    ;;
  ph1-progress)
    sqlite3 "$DB" "UPDATE todos SET status='done' WHERE id='ph1-t01';"
    sqlite3 "$DB" "UPDATE todos SET status='in_progress' WHERE id='ph1-t02';"
    sqlite3 "$DB" "INSERT OR REPLACE INTO session_state(key,value) VALUES('activity','Creating config files');"
    echo "Phase 1: 1/3 done"
    ;;
  ph1-more)
    sqlite3 "$DB" "UPDATE todos SET status='done' WHERE id='ph1-t02';"
    sqlite3 "$DB" "UPDATE todos SET status='in_progress' WHERE id='ph1-t03';"
    sqlite3 "$DB" "INSERT OR REPLACE INTO session_state(key,value) VALUES('activity','Installing dependencies');"
    echo "Phase 1: 2/3 done"
    ;;
  ph1-done)
    sqlite3 "$DB" "UPDATE todos SET status='done' WHERE id='ph1-t03';"
    sqlite3 "$DB" "UPDATE phases SET status='done' WHERE id='ph1';"
    sqlite3 "$DB" "UPDATE phases SET status='in_progress' WHERE id='ph2';"
    sqlite3 "$DB" "DELETE FROM todos;"
    sqlite3 "$DB" "INSERT INTO todos(id,title,status) VALUES('ph2-t01','Core module','pending'),('ph2-t02','Error handling','pending'),('ph2-t03','Tests','pending'),('ph2-t04','Review','pending');"
    sqlite3 "$DB" "INSERT OR REPLACE INTO session_state(key,value) VALUES('activity','Building core module'),('total_tasks','4'),('phase_heading','Phase 2: Build');"
    echo "Phase 1 complete! Starting Phase 2"
    ;;
  ph2-progress)
    sqlite3 "$DB" "UPDATE todos SET status='done' WHERE id='ph2-t01';"
    sqlite3 "$DB" "UPDATE todos SET status='done' WHERE id='ph2-t02';"
    sqlite3 "$DB" "UPDATE todos SET status='in_progress' WHERE id='ph2-t03';"
    sqlite3 "$DB" "INSERT OR REPLACE INTO session_state(key,value) VALUES('activity','Writing tests');"
    echo "Phase 2: 2/4 done"
    ;;
  ph2-done)
    sqlite3 "$DB" "UPDATE todos SET status='done' WHERE id='ph2-t03';"
    sqlite3 "$DB" "UPDATE todos SET status='done' WHERE id='ph2-t04';"
    sqlite3 "$DB" "UPDATE phases SET status='done' WHERE id='ph2';"
    sqlite3 "$DB" "UPDATE phases SET status='in_progress' WHERE id='ph3';"
    sqlite3 "$DB" "DELETE FROM todos;"
    sqlite3 "$DB" "INSERT INTO todos(id,title,status) VALUES('ph3-t01','Deploy','pending'),('ph3-t02','Smoke tests','pending');"
    sqlite3 "$DB" "INSERT OR REPLACE INTO session_state(key,value) VALUES('activity','Deploying to staging'),('total_tasks','2'),('phase_heading','Phase 3: Ship');"
    echo "Phase 2 complete! Starting Phase 3"
    ;;
  ph3-done)
    sqlite3 "$DB" "UPDATE todos SET status='done' WHERE id='ph3-t01';"
    sqlite3 "$DB" "UPDATE todos SET status='done' WHERE id='ph3-t02';"
    sqlite3 "$DB" "UPDATE phases SET status='done' WHERE id='ph3';"
    sqlite3 "$DB" "INSERT OR REPLACE INTO session_state(key,value) VALUES('activity','All phases complete!');"
    echo "All done!"
    ;;
esac
