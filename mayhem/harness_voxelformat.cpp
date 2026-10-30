// libFuzzer harness for vengi's voxel format loaders. One source, compiled once per format:
// -DFUZZ_EXT=\"vox\" selects the file extension loadFormat() dispatches on. Bytes only come from
// the fuzzer (through an in-memory archive); the only file I/O is the scratch dir the vengi app
// object creates for its config/data under $TMPDIR.
#include "app/CommandlineApp.h"
#include "core/Log.h"
#include "core/SharedPtr.h"
#include "core/String.h"
#include "core/TimeProvider.h"
#include "io/Filesystem.h"
#include "io/FormatDescription.h"
#include "io/MemoryArchive.h"
#include "scenegraph/SceneGraph.h"
#include "palette/FormatConfig.h"
#include "voxelformat/Format.h"
#include "voxelformat/FormatConfig.h"
#include "voxelformat/VolumeFormat.h"

#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifndef FUZZ_EXT
#error "FUZZ_EXT must name the input file extension, e.g. -DFUZZ_EXT=\"vox\""
#endif

namespace {

class FuzzApp : public app::CommandlineApp {
public:
	FuzzApp(const io::FilesystemPtr &filesystem, const core::TimeProviderPtr &timeProvider)
		: app::CommandlineApp(filesystem, timeProvider, 1) {
		init(ORGANISATION, "fuzz");
	}
	bool createPid() override {
		return false;
	}
	bool start() {
		while (_curState < app::AppState::Running) {
			onFrame();
		}
		return _curState == app::AppState::Running;
	}
};

FuzzApp *fuzzApp = nullptr;

// The app object installs process-wide handlers (crash signals via backward, an alarm handler that
// exit()s, graceful-shutdown handlers) and a sigaltstack it frees again. They replace the ones libFuzzer
// and ASan installed, so an exec timeout became exit(1) and a crash handler ran on freed memory. The
// harness puts back exactly what was there before the app was constructed; the loaders need none of them.
struct SignalState {
	struct sigaction actions[NSIG];
	stack_t altStack;

	void save() {
		for (int sig = 1; sig < NSIG; ++sig) {
			sigaction(sig, nullptr, &actions[sig]);
		}
		sigaltstack(nullptr, &altStack);
	}
	void restore() const {
		for (int sig = 1; sig < NSIG; ++sig) {
			sigaction(sig, &actions[sig], nullptr);
		}
		sigaltstack(&altStack, nullptr);
	}
};

} // namespace

extern "C" int LLVMFuzzerInitialize(int *, char ***) {
	const char *tmp = getenv("TMPDIR");
	char dir[4096];
	snprintf(dir, sizeof(dir), "%s/vengi-fuzz-XXXXXX", tmp && *tmp ? tmp : "/tmp");
	if (mkdtemp(dir) == nullptr) {
		return 0;
	}
	setenv("HOME", dir, 1);
	setenv("XDG_DATA_HOME", dir, 1);
	setenv("XDG_CONFIG_HOME", dir, 1);
	setenv("XDG_CACHE_HOME", dir, 1);
	const io::FilesystemPtr filesystem = core::make_shared<io::Filesystem>();
	const core::TimeProviderPtr timeProvider = core::make_shared<core::TimeProvider>();
	SignalState signals;
	signals.save();
	fuzzApp = new FuzzApp(filesystem, timeProvider);
	const bool started = fuzzApp->start();
	signals.restore();
	if (!started) {
		abort();
	}
	Log::setLevel(static_cast<Log::Level>(static_cast<int>(Log::Level::Error) + 1));
	palette::FormatConfig::init();
	voxelformat::FormatConfig::init();
	return 0;
}

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
	if (size == 0) {
		return -1;
	}
	static const core::String name = "input." FUZZ_EXT;
	io::MemoryArchivePtr archive = io::openMemoryArchive();
	if (!archive->add(name, data, size)) {
		return -1;
	}
	io::FileDescription fileDesc;
	fileDesc.set(name);
	scenegraph::SceneGraph sceneGraph;
	voxelformat::LoadContext ctx;
	if (!voxelformat::loadFormat(fileDesc, archive, sceneGraph, ctx)) {
		return -1;
	}
	return 0;
}
