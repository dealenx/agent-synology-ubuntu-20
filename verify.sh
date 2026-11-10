#!/bin/bash
# Throwaway/CI test: reproduce the vendor failure, then prove install-abb.sh fixes it.
set -u
cd /root/ABB

echo "=== STEP 1: reproduce (real uname -> host kernel headers missing) ==="
mv /usr/local/sbin/uname /tmp/uname.wrap
PATH=/usr/sbin:/usr/bin:/sbin:/bin ./install.run > /tmp/step1.log 2>&1
rc1=$?
grep -E "no installation candidate|install linux-headers.* failed" /tmp/step1.log
mv /tmp/uname.wrap /usr/local/sbin/uname
[ "$rc1" -ne 0 ] || { echo "FAIL: expected reproduction to fail"; exit 1; }
echo "reproduced as expected (exit=$rc1)"

echo
echo "=== STEP 2: install-abb.sh ==="
bash ./install-abb.sh > /tmp/step2.log 2>&1
rc2=$?
grep -E "\[abb-install\]|The installation is complete" /tmp/step2.log || tail -20 /tmp/step2.log
[ "$rc2" -eq 0 ] || { echo "FAIL: install-abb.sh exit=$rc2"; tail -40 /tmp/step2.log; exit 1; }
echo "PASS: install-abb.sh exit=0"
