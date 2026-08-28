awk -F' \\[com[^\\]]*\\] ' '{
  if (NF < 2) { print $0; next }
  split($2, parts, ": ")
  print "• " parts[1]
  if (parts[2] != "") {
    n = split(parts[2], ops, ", ")
    for (i = 1; i <= n; i++) print "    └─ " ops[i]
  }
}'
