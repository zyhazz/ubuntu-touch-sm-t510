/* LD_PRELOAD diagnostic: log si_addr, PC and /proc/self/maps on SIGBUS,
 * then chain to the handler the program installed. */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <ucontext.h>
#include <unistd.h>

static struct sigaction prog_act;
static int (*real_sigaction)(int, const struct sigaction *, struct sigaction *);

static void copy_file(const char *src, int out)
{
	char buf[4096];
	ssize_t n;
	int in = open(src, O_RDONLY);
	if (in < 0)
		return;
	while ((n = read(in, buf, sizeof(buf))) > 0)
		write(out, buf, n);
	close(in);
}

static void handler(int sig, siginfo_t *si, void *uc_)
{
	ucontext_t *uc = uc_;
	char line[256];
	int out = open("/tmp/sigbus-trace.txt", O_WRONLY | O_CREAT | O_APPEND, 0644);
	if (out >= 0) {
		int n = snprintf(line, sizeof(line),
			"SIGBUS code=%d addr=%p pc=%llx lr=%llx\n", si->si_code, si->si_addr,
			(unsigned long long)uc->uc_mcontext.pc,
			(unsigned long long)uc->uc_mcontext.regs[30]);
		write(out, line, n);
		copy_file("/proc/self/maps", out);
		close(out);
	}
	if (prog_act.sa_flags & SA_SIGINFO && prog_act.sa_sigaction)
		prog_act.sa_sigaction(sig, si, uc_);
	else if (prog_act.sa_handler != SIG_DFL && prog_act.sa_handler != SIG_IGN)
		prog_act.sa_handler(sig);
	else {
		signal(sig, SIG_DFL);
		raise(sig);
	}
}

int sigaction(int sig, const struct sigaction *act, struct sigaction *old)
{
	if (!real_sigaction)
		real_sigaction = dlsym(RTLD_NEXT, "sigaction");
	if (sig == SIGBUS && act) {
		struct sigaction ours;
		if (old)
			*old = prog_act;
		prog_act = *act;
		memset(&ours, 0, sizeof(ours));
		ours.sa_sigaction = handler;
		ours.sa_flags = SA_SIGINFO;
		sigemptyset(&ours.sa_mask);
		return real_sigaction(sig, &ours, NULL);
	}
	return real_sigaction(sig, act, old);
}
