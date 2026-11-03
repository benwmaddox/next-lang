# Whitespace normalisation for .nl files (nlc fmt): leading tabs become 4 spaces, trailing spaces go, runs of blank lines
# shrink to one, the file ends with exactly one newline. Text inside a """ literal is left exactly as it is.
BEGIN { inside = 0; blank = 0; started = 0 }
{
    line = $0
    sub(/\r$/, "", line)
    if (!inside) {
        while (match(line, /^ *\t/)) {
            lead = substr(line, 1, RLENGTH - 1)
            line = lead "    " substr(line, RLENGTH + 1)
        }
        sub(/[ \t]+$/, "", line)
    }
    count = gsub(/"""/, "&", line)
    if (!inside && line == "") {
        if (started) blank++
        next
    }
    if (blank > 0 && !inside) { print ""; blank = 0 }
    started = 1
    print line
    if (count % 2 == 1) inside = !inside
}
