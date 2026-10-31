import sqlite3, sys, os
p = sys.argv[1]
if os.path.exists(p): os.remove(p)
c = sqlite3.connect(p)
c.execute("create table items (id integer primary key, v integer, name text, price integer)")
names = ["widget", "gadget <pro>", "thing & co", "the \"best\" one", "plain"]
c.executemany("insert into items values (?,?,?,?)",
              ((i, (i * 2654435761) % 1000000007, names[i % 5] + " %d" % i, 100 + (i * 37) % 9900) for i in range(5000)))
c.commit()
