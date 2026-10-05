#!/usr/bin/env python3
"""Kill the actual Swift persistence writer while it saves 1 MiB captures, then reopen.
No deterministic claim about exactly which CPU instruction receives SIGKILL is made.
"""
import pathlib, subprocess, tempfile, time, sqlite3
root = pathlib.Path(__file__).resolve().parents[1]
probe = pathlib.Path(subprocess.check_output(['swift', 'build', '--show-bin-path'], cwd=root, text=True).strip()) / 'QueueProbe'
for run in range(12):
    with tempfile.TemporaryDirectory(prefix='snapnest-crash-') as directory:
        db = pathlib.Path(directory) / 'queue.sqlite'
        with tempfile.TemporaryFile() as log:
            process = subprocess.Popen([str(probe), 'write', str(db)], stdout=log, stderr=subprocess.PIPE)
            time.sleep(0.03 + run * 0.007)
            process.kill()
            process.communicate(timeout=10)
            log.seek(0)
            committed = set(log.read().decode().splitlines())
        output = subprocess.check_output([str(probe), 'check', str(db)], text=True).strip()
        with sqlite3.connect(db) as connection:
            rows = connection.execute('SELECT id,length(image),size,state FROM captures').fetchall()
        ids = {row[0] for row in rows}
        assert committed <= ids, 'A capture acknowledged as saved was lost'
        assert len(ids) - len(committed) <= 1, 'Unexpected unacknowledged commits'
        assert all(row[1:] == (1024*1024, 1024*1024, 'pending') for row in rows), 'Partial/corrupt capture'
        assert output.startswith('ok '), output
        print(f'run {run+1:02d}: integrity ok; {len(committed)} acknowledged, {len(rows)} intact after SIGKILL')
print('PASS: 12 real process kills; every acknowledged capture survived; no partial rows')
