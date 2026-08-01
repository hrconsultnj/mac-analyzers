#pragma once
// Bridges libproc to Swift — proc_pid_rusage / proc_listallpids are not in
// the Darwin module map. Header-only; the .c file exists to satisfy SPM.
#include <libproc.h>
#include <sys/resource.h>
