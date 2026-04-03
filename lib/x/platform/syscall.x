; syscall.x -- x86_64 and i386/BSD syscall tables
(import x/core/list)

; x86_64 syscall name table (267 entries, index = syscall number)

(def x86_64-syscall-names
  (list
    (lit read)
    ;   0

    (lit write)
    ;   1

    (lit open)
    ;   2

    (lit close)
    ;   3

    (lit stat)
    ;   4

    (lit fstat)
    ;   5

    (lit lstat)
    ;   6

    (lit poll)
    ;   7

    (lit lseek)
    ;   8

    (lit mmap)
    ;   9

    (lit mprotect)
    ;  10

    (lit munmap)
    ;  11

    (lit brk)
    ;  12

    (lit rt_sigaction)
    ;  13

    (lit rt_sigprocmask)
    ;  14

    (lit rt_sigreturn)
    ;  15

    (lit ioctl)
    ;  16

    (lit pread64)
    ;  17

    (lit pwrite64)
    ;  18

    (lit readv)
    ;  19

    (lit writev)
    ;  20

    (lit access)
    ;  21

    (lit pipe)
    ;  22

    (lit select)
    ;  23

    (lit sched_yield)
    ;  24

    (lit mremap)
    ;  25

    (lit msync)
    ;  26

    (lit mincore)
    ;  27

    (lit madvise)
    ;  28

    (lit shmget)
    ;  29

    (lit shmat)
    ;  30

    (lit shmctl)
    ;  31

    (lit dup)
    ;  32

    (lit dup2)
    ;  33

    (lit pause)
    ;  34

    (lit nanosleep)
    ;  35

    (lit getitimer)
    ;  36

    (lit alarm)
    ;  37

    (lit setitimer)
    ;  38

    (lit getpid)
    ;  39

    (lit sendfile)
    ;  40

    (lit socket)
    ;  41

    (lit connect)
    ;  42

    (lit accept)
    ;  43

    (lit sendto)
    ;  44

    (lit recvfrom)
    ;  45

    (lit sendmsg)
    ;  46

    (lit recvmsg)
    ;  47

    (lit shutdown)
    ;  48

    (lit bind)
    ;  49

    (lit listen)
    ;  50

    (lit getsockname)
    ;  51

    (lit getpeername)
    ;  52

    (lit socketpair)
    ;  53

    (lit setsockopt)
    ;  54

    (lit getsockopt)
    ;  55

    (lit clone)
    ;  56

    (lit fork)
    ;  57

    (lit vfork)
    ;  58

    (lit execve)
    ;  59

    (lit exit)
    ;  60

    (lit wait4)
    ;  61

    (lit kill)
    ;  62

    (lit uname)
    ;  63

    (lit semget)
    ;  64

    (lit semop)
    ;  65

    (lit semctl)
    ;  66

    (lit shmdt)
    ;  67

    (lit msgget)
    ;  68

    (lit msgsnd)
    ;  69

    (lit msgrcv)
    ;  70

    (lit msgctl)
    ;  71

    (lit fcntl)
    ;  72

    (lit flock)
    ;  73

    (lit fsync)
    ;  74

    (lit fdatasync)
    ;  75

    (lit truncate)
    ;  76

    (lit ftruncate)
    ;  77

    (lit getdents)
    ;  78

    (lit getcwd)
    ;  79

    (lit chdir)
    ;  80

    (lit fchdir)
    ;  81

    (lit rename)
    ;  82

    (lit mkdir)
    ;  83

    (lit rmdir)
    ;  84

    (lit creat)
    ;  85

    (lit link)
    ;  86

    (lit unlink)
    ;  87

    (lit symlink)
    ;  88

    (lit readlink)
    ;  89

    (lit chmod)
    ;  90

    (lit fchmod)
    ;  91

    (lit chown)
    ;  92

    (lit fchown)
    ;  93

    (lit lchown)
    ;  94

    (lit umask)
    ;  95

    (lit gettimeofday)
    ;  96

    (lit getrlimit)
    ;  97

    (lit getrusage)
    ;  98

    (lit sysinfo)
    ;  99

    (lit times)
    ; 100

    (lit ptrace)
    ; 101

    (lit getuid)
    ; 102

    (lit syslog)
    ; 103

    (lit getgid)
    ; 104

    (lit setuid)
    ; 105

    (lit setgid)
    ; 106

    (lit geteuid)
    ; 107

    (lit getegid)
    ; 108

    (lit setpgid)
    ; 109

    (lit getppid)
    ; 110

    (lit getpgrp)
    ; 111

    (lit setsid)
    ; 112

    (lit setreuid)
    ; 113

    (lit setregid)
    ; 114

    (lit getgroups)
    ; 115

    (lit setgroups)
    ; 116

    (lit setresuid)
    ; 117

    (lit getresuid)
    ; 118

    (lit setresgid)
    ; 119

    (lit getresgid)
    ; 120

    (lit getpgid)
    ; 121

    (lit setfsuid)
    ; 122

    (lit setfsgid)
    ; 123

    (lit getsid)
    ; 124

    (lit capget)
    ; 125

    (lit capset)
    ; 126

    (lit rt_sigpending)
    ; 127

    (lit rt_sigtimedwait)
    ; 128

    (lit rt_sigqueueinfo)
    ; 129

    (lit rt_sigsuspend)
    ; 130

    (lit sigaltstack)
    ; 131

    (lit utime)
    ; 132

    (lit mknod)
    ; 133

    (lit uselib)
    ; 134

    (lit personality)
    ; 135

    (lit ustat)
    ; 136

    (lit statfs)
    ; 137

    (lit fstatfs)
    ; 138

    (lit sysfs)
    ; 139

    (lit getpriority)
    ; 140

    (lit setpriority)
    ; 141

    (lit sched_setparam)
    ; 142

    (lit sched_getparam)
    ; 143

    (lit sched_setscheduler)
    ; 144

    (lit sched_getscheduler)
    ; 145

    (lit sched_get_priority_max)
    ; 146

    (lit sched_get_priority_min)
    ; 147

    (lit sched_rr_get_interval)
    ; 148

    (lit mlock)
    ; 149

    (lit munlock)
    ; 150

    (lit mlockall)
    ; 151

    (lit munlockall)
    ; 152

    (lit vhangup)
    ; 153

    (lit modify_ldt)
    ; 154

    (lit pivot_root)
    ; 155

    (lit _sysctl)
    ; 156

    (lit prctl)
    ; 157

    (lit arch_prctl)
    ; 158

    (lit adjtimex)
    ; 159

    (lit setrlimit)
    ; 160

    (lit chroot)
    ; 161

    (lit sync)
    ; 162

    (lit acct)
    ; 163

    (lit settimeofday)
    ; 164

    (lit mount)
    ; 165

    (lit umount2)
    ; 166

    (lit swapon)
    ; 167

    (lit swapoff)
    ; 168

    (lit reboot)
    ; 169

    (lit sethostname)
    ; 170

    (lit setdomainname)
    ; 171

    (lit iopl)
    ; 172

    (lit ioperm)
    ; 173

    (lit create_module)
    ; 174

    (lit init_module)
    ; 175

    (lit delete_module)
    ; 176

    (lit get_kernel_syms)
    ; 177

    (lit query_module)
    ; 178

    (lit quotactl)
    ; 179

    (lit nfsservctl)
    ; 180

    (lit getpmsg)
    ; 181

    (lit putpmsg)
    ; 182

    (lit afs_syscall)
    ; 183

    (lit tuxcall)
    ; 184

    (lit security)
    ; 185

    (lit gettid)
    ; 186

    (lit readahead)
    ; 187

    (lit setxattr)
    ; 188

    (lit lsetxattr)
    ; 189

    (lit fsetxattr)
    ; 190

    (lit getxattr)
    ; 191

    (lit lgetxattr)
    ; 192

    (lit fgetxattr)
    ; 193

    (lit listxattr)
    ; 194

    (lit llistxattr)
    ; 195

    (lit flistxattr)
    ; 196

    (lit removexattr)
    ; 197

    (lit lremovexattr)
    ; 198

    (lit fremovexattr)
    ; 199

    (lit tkill)
    ; 200

    (lit time)
    ; 201

    (lit futex)
    ; 202

    (lit sched_setaffinity)
    ; 203

    (lit sched_getaffinity)
    ; 204

    (lit set_thread_area)
    ; 205

    (lit io_setup)
    ; 206

    (lit io_destroy)
    ; 207

    (lit io_getevents)
    ; 208

    (lit io_submit)
    ; 209

    (lit io_cancel)
    ; 210

    (lit get_thread_area)
    ; 211

    (lit lookup_dcookie)
    ; 212

    (lit epoll_create)
    ; 213

    (lit epoll_ctl_old)
    ; 214

    (lit epoll_wait_old)
    ; 215

    (lit remap_file_pages)
    ; 216

    (lit getdents64)
    ; 217

    (lit set_tid_address)
    ; 218

    (lit restart_syscall)
    ; 219

    (lit semtimedop)
    ; 220

    (lit fadvise64)
    ; 221

    (lit timer_create)
    ; 222

    (lit timer_settime)
    ; 223

    (lit timer_gettime)
    ; 224

    (lit timer_getoverrun)
    ; 225

    (lit timer_delete)
    ; 226

    (lit clock_settime)
    ; 227

    (lit clock_gettime)
    ; 228

    (lit clock_getres)
    ; 229

    (lit clock_nanosleep)
    ; 230

    (lit exit_group)
    ; 231

    (lit epoll_wait)
    ; 232

    (lit epoll_ctl)
    ; 233

    (lit tgkill)
    ; 234

    (lit utimes)
    ; 235

    (lit vserver)
    ; 236

    (lit mbind)
    ; 237

    (lit set_mempolicy)
    ; 238

    (lit get_mempolicy)
    ; 239

    (lit mq_open)
    ; 240

    (lit mq_unlink)
    ; 241

    (lit mq_timedsend)
    ; 242

    (lit mq_timedreceive)
    ; 243

    (lit mq_notify)
    ; 244

    (lit mq_getsetattr)
    ; 245

    (lit kexec_load)
    ; 246

    (lit waitid)
    ; 247

    (lit add_key)
    ; 248

    (lit request_key)
    ; 249

    (lit keyctl)
    ; 250

    (lit ioprio_set)
    ; 251

    (lit ioprio_get)
    ; 252

    (lit inotify_init)
    ; 253

    (lit inotify_add_watch)
    ; 254

    (lit inotify_rm_watch)
    ; 255

    (lit migrate_pages)
    ; 256

    (lit openat)
    ; 257

    (lit mkdirat)
    ; 258

    (lit mknodat)
    ; 259

    (lit fchownat)
    ; 260

    (lit futimesat)
    ; 261

    (lit newfstatat)
    ; 262

    (lit unlinkat)
    ; 263

    (lit renameat)
    ; 264

    (lit linkat)
    ; 265

    (lit symlinkat)
    ; 266

    (lit readlinkat)
    ; 267

    (lit fchmodat)
    ; 268

    (lit faccessat)
    ; 269

    (lit pselect6)
    ; 270

    (lit ppoll)
    ; 271

    (lit unshare)
    ; 272

    (lit set_robust_list)
    ; 273

    (lit get_robust_list)
    ; 274

    (lit splice)
    ; 275

    (lit tee)
    ; 276

    (lit sync_file_range)
    ; 277

    (lit vmsplice)
    ; 278

    (lit move_pages)
    ; 279

    (lit utimensat)
    ; 280

    (lit epoll_pwait)
    ; 281

    (lit signalfd)
    ; 282

    (lit timerfd_create)
    ; 283

    (lit eventfd)
    ; 284

    (lit fallocate)
    ; 285

    (lit timerfd_settime)
    ; 286

    (lit timerfd_gettime)
    ; 287

    (lit accept4)
    ; 288

    (lit signalfd4)
    ; 289

    (lit eventfd2)
    ; 290

    (lit epoll_create1)
    ; 291

    (lit dup3)
    ; 292

    (lit pipe2)
    ; 293

    (lit inotify_init1)
    ; 294

    (lit preadv)
    ; 295

    (lit pwritev)
    ; 296

    (lit rt_tgsigqueueinfo)
    ; 297

    (lit perf_event_open)
    ; 298

    (lit recvmmsg)
    ; 299

    (lit fanotify_init)
    ; 300

    (lit fanotify_mark)
    ; 301

    (lit prlimit64)
    ; 302

    (lit name_to_handle_at)
    ; 303

    (lit open_by_handle_at)
    ; 304

    (lit clock_adjtime)
    ; 305

    (lit syncfs)
    ; 306

    (lit sendmmsg)
    ; 307

    (lit setns)
    ; 308

    (lit getcpu)
    ; 309

    (lit process_vm_readv)
    ; 310

    (lit process_vm_writev)
    ; 311

    (lit kcmp)
    ; 312

    (lit finit_module)
    ; 313
))
; i386 / BSD / Darwin syscall name table (index = syscall number)

(def i386-syscall-names
  (list
    (lit none)
    ;   0

    (lit exit)
    ;   1

    (lit fork)
    ;   2

    (lit read)
    ;   3

    (lit write)
    ;   4

    (lit open)
    ;   5

    (lit close)
    ;   6

    (lit waitpid)
    ;   7

    (lit creat)
    ;   8

    (lit link)
    ;   9

    (lit unlink)
    ;  10

    (lit execve)
    ;  11

    (lit chdir)
    ;  12

    (lit time)
    ;  13

    (lit mknod)
    ;  14

    (lit chmod)
    ;  15

    (lit lchown)
    ;  16

    (lit nil)
    ;  17

    (lit stat)
    ;  18

    (lit lseek)
    ;  19

    (lit getpid)
    ;  20

    (lit mount)
    ;  21

    (lit oldmount)
    ;  22

    (lit setuid)
    ;  23

    (lit getuid)
    ;  24

    (lit stime)
    ;  25

    (lit ptrace)
    ;  26

    (lit alarm)
    ;  27

    (lit fstat)
    ;  28

    (lit pause)
    ;  29

    (lit utime)
    ;  30

    (lit nil)
    ;  31

    (lit nil)
    ;  32

    (lit access)
    ;  33

    (lit nice)
    ;  34

    (lit nil)
    ;  35

    (lit sync)
    ;  36

    (lit kill)
    ;  37

    (lit rename)
    ;  38

    (lit mkdir)
    ;  39

    (lit rmdir)
    ;  40

    (lit dup)
    ;  41

    (lit pipe)
    ;  42

    (lit times)
    ;  43

    (lit nil)
    ;  44

    (lit brk)
    ;  45

    (lit setgid)
    ;  46

    (lit getgid)
    ;  47

    (lit signal)
    ;  48

    (lit geteuid)
    ;  49

    (lit getegid)
    ;  50

    (lit acct)
    ;  51

    (lit umount)
    ;  52

    (lit nil)
    ;  53

    (lit ioctl)
    ;  54

    (lit fcntl)
    ;  55

    (lit nil)
    ;  56

    (lit setpgid)
    ;  57

    (lit nil)
    ;  58

    (lit olduname)
    ;  59

    (lit umask)
    ;  60

    (lit chroot)
    ;  61

    (lit ustat)
    ;  62

    (lit dup2)
    ;  63

    (lit getppid)
    ;  64

    (lit getpgrp)
    ;  65

    (lit setsid)
    ;  66

    (lit sigaction)
    ;  67

    (lit sgetmask)
    ;  68

    (lit ssetmask)
    ;  69

    (lit setreuid)
    ;  70

    (lit setregid)
    ;  71

    (lit sigsuspend)
    ;  72

    (lit sigpending)
    ;  73

    (lit sethostname)
    ;  74

    (lit setrlimit)
    ;  75

    (lit getrlimit)
    ;  76

    (lit getrusage)
    ;  77

    (lit gettimeofday)
    ;  78

    (lit settimeofday)
    ;  79

    (lit getgroups)
    ;  80

    (lit setgroups)
    ;  81

    (lit oldselect)
    ;  82

    (lit symlink)
    ;  83

    (lit lstat)
    ;  84

    (lit readlink)
    ;  85

    (lit uselib)
    ;  86

    (lit swapon)
    ;  87

    (lit reboot)
    ;  88

    (lit readdir)
    ;  89

    (lit mmap)
    ;  90

    (lit munmap)
    ;  91

    (lit truncate)
    ;  92

    (lit ftruncate)
    ;  93

    (lit fchmod)
    ;  94

    (lit fchown)
    ;  95

    (lit getpriority)
    ;  96

    (lit setpriority)
    ;  97

    (lit nil)
    ;  98

    (lit statfs)
    ;  99

    (lit fstatfs)
    ; 100

    (lit ioperm)
    ; 101

    (lit socketcall)
    ; 102

    (lit syslog)
    ; 103

    (lit setitimer)
    ; 104

    (lit getitimer)
    ; 105

    (lit stat)
    ; 106

    (lit lstat)
    ; 107

    (lit fstat)
    ; 108

    (lit uname)
    ; 109

    (lit iopl)
    ; 110

    (lit vhangup)
    ; 111

    (lit idle)
    ; 112

    (lit vm86old)
    ; 113

    (lit wait4)
    ; 114

    (lit swapoff)
    ; 115

    (lit sysinfo)
    ; 116

    (lit ipc)
    ; 117

    (lit fsync)
    ; 118

    (lit sigreturn)
    ; 119

    (lit clone)
    ; 120

    (lit setdomainname)
    ; 121

    (lit uname)
    ; 122

    (lit modify-ldt)
    ; 123

    (lit adjtimex)
    ; 124

    (lit mprotect)
    ; 125

    (lit sigprocmask)
    ; 126

    (lit create-module)
    ; 127

    (lit init-module)
    ; 128

    (lit delete-module)
    ; 129

    (lit get-kernel-syms)
    ; 130

    (lit quotactl)
    ; 131

    (lit getpgid)
    ; 132

    (lit fchdir)
    ; 133

    (lit bdflush)
    ; 134

    (lit sysfs)
    ; 135

    (lit personality)
    ; 136

    (lit nil)
    ; 137

    (lit setfsuid)
    ; 138

    (lit getfsgid)
    ; 139

    (lit llseek)
    ; 140

    (lit getdents)
    ; 141

    (lit select)
    ; 142

    (lit flock)
    ; 143

    (lit msync)
    ; 144

    (lit readv)
    ; 145

    (lit writev)
    ; 146

    (lit getsid)
    ; 147

    (lit fdatasync)
    ; 148

    (lit sysctl)
    ; 149

    (lit mlock)
    ; 150

    (lit munlock)
    ; 151

    (lit mlockall)
    ; 152

    (lit munlockall)
    ; 153

    (lit sched-setparam)
    ; 154

    (lit sched-getparam)
    ; 155

    (lit sched-setscheduler)
    ; 156

    (lit sched-getscheduler)
    ; 157

    (lit sched-yield)
    ; 158

    (lit sched-get-priority-max)
    ; 159

    (lit sched-get-priority-min)
    ; 160

    (lit sched-rr-get-interval)
    ; 161

    (lit nanosleep)
    ; 162

    (lit mremap)
    ; 163

    (lit setresuid)
    ; 164

    (lit getresuid)
    ; 165

    (lit vm86)
    ; 166

    (lit query-module)
    ; 167

    (lit poll)
    ; 168

    (lit nfsservctl)
    ; 169

    (lit setresgid)
    ; 170

    (lit getresgid)
    ; 171

    (lit prctl)
    ; 172

    (lit rt-sigreturn)
    ; 173

    (lit rt-sigaction)
    ; 174

    (lit rt-sigprocmask)
    ; 175

    (lit rt-sigpending)
    ; 176

    (lit rt-sigtimedwait)
    ; 177

    (lit rt-sigqueueinfo)
    ; 178

    (lit rt-sigsuspend)
    ; 179

    (lit pread)
    ; 180

    (lit pwrite)
    ; 181

    (lit chown)
    ; 182

    (lit getcwd)
    ; 183

    (lit capget)
    ; 184

    (lit capset)
    ; 185

    (lit sigaltstack)
    ; 186

    (lit sendfile)
    ; 187

    (lit nil)
    ; 188

    (lit nil)
    ; 189

    (lit vfork)
    ; 190
))
; syscall-id: look up a syscall number by name.

; Uses the x86_64 table by default; falls back to i386/BSD.

; Returns the index (= syscall number) or -1 if not found.

(def syscall-id
  (fn (call)
    (let ((n (index-of call x86_64-syscall-names)))
      (if (>= n 0) n (index-of call i386-syscall-names)))))

(doc (provide x/platform/syscall syscall-id x86_64-syscall-names i386-syscall-names)
  "Syscall number tables for x86_64 and i386/BSD. Maps symbolic names to syscall numbers.")
