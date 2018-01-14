# rebuild-native
Rebuild Debian packages using GCC -march=native option

This script must be run with root privileges. The --preserve-environment
option MUST be passed to the gain-root-command used.
eg:
Using su: su -p -c "script"
Using sudo: sudo -E script
