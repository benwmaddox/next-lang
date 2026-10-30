import sqlite3, sys, os
p = sys.argv[1]
if os.path.exists(p): os.remove(p)
c = sqlite3.connect(p)
c.execute("create table items (id integer primary key, v integer, name text)")
c.executemany("insert into items values (?,?,?)", ((i, (i * 2654435761) % 1000000007, "item%d" % i) for i in range(5000)))
c.commit()
