-- generate.lua --
-- Run as `lua docker/generate.lua` (from the project root)
-- Will generate a series of Dockerfiles in this folder (docker) with the format:
-- Dockerfile-[DISTRO]-[RELEASE]-[LLVM VERSION]-[CMAKE/MAKE]
--
-- Example running a build/test (also run from the project root):
-- docker build -f docker/Dockerfile-ubuntu-18.04-11-cmake


local args = {...}

local llvms = {"3.8", "5.0", "6.0", "7", "8", "9", "10", "11", "12"}
local buildsystems = {"make", "cmake"}

local releasenames = {
	["16.04"] = "xenial",
	["18.04"] = "bionic"
}

local requiresrepo = {
	["3.8"] = true,
	["11"] = true,
	["12"] = true
}

local argmatrix = {}

for _,llvm in ipairs(llvms) do
	for _,buildsystem in ipairs(buildsystems) do
		local release = llvm == "3.8" and "16.04" or "18.04"
		local options = {
			LLVM = llvm,
			DISTRO = "ubuntu",
			RELEASE = release,
			RELEASENAME = releasenames[release],
			BUILDSYSTEM = buildsystem,
			THREADS = 8
		}
		if buildsystem == "cmake" and llvm == "3.8" or llvm == "7" then
			goto next
		end
		table.insert(argmatrix, options)
		::next::
	end
end

function createDockerfile(options)
	local lines = {}
	local writeln = function(str)
		table.insert(lines, str)
		table.insert(lines, "\n")
	end
	local expand = function(str)
		return str:gsub("@([^@]+)@",function(name)
			if options[name] then
				return options[name]
			else
				print("Found invalid substitution '"..name.."' in generate.lua docker template")
				os.exit(2)
			end
		end)
	end
	writeln[[
# vim: ft=dockerfile

FROM @DISTRO@:@RELEASE@
ENV DEBIAN_FRONTEND noninteractive

# Base packages
RUN apt-get update -qq && apt-get install -qq \
	apt-utils apt-transport-https ca-certificates \
	software-properties-common \
	build-essential \
	wget git cmake
# Common Dependencies
RUN apt-get install -qq libedit-dev libncurses-dev zlib1g-dev

# Install LLVM & Clang
]]

	if requiresrepo[options.LLVM] then
		writeln[[
RUN wget -O - https://apt.llvm.org/llvm-snapshot.gpg.key | apt-key add -
RUN add-apt-repository -y "deb http://apt.llvm.org/@RELEASENAME@/ llvm-toolchain-@RELEASENAME@-@LLVM@ main"
RUN for i in {1..5}; do apt-get update -qq && break || sleep 15; done
]]
	end
	if options.LLVM == "3.8" then
		writeln[[
RUN bash -c "echo 'Package: *' >> /etc/apt/preferences.d/llvm-600" ;\
    bash -c "echo 'Pin: origin apt.llvm.org' >> /etc/apt/preferences.d/llvm-600" ;\
    bash -c "echo 'Pin-Priority: 600' >> /etc/apt/preferences.d/llvm-600" ;\
    cat /etc/apt/preferences.d/llvm-600
]]
	end

	writeln[[
RUN apt-get install -y llvm-@LLVM@-dev clang-@LLVM@ libclang-@LLVM@-dev

COPY . /terra
]]

	if options.BUILDSYSTEM == "cmake" then
		writeln[[
ENV CMAKE_PREFIX_PATH /usr/lib/llvm-@LLVM@:/usr/lib/llvm-@LLVM@
RUN cd /terra/build && \
	cmake -DCMAKE_INSTALL_PREFIX=/terra_install .. && \
	make install -j@THREADS@ && \
    ctest --output-on-failure -j@THREADS@
]]
	elseif options.BUILDSYSTEM == "make" then
		writeln[[
RUN cd /terra && make PREFIX=/terra_install LLVM_CONFIG=$(which llvm-config-@LLVM@) CLANG=$(which clang-@LLVM@) test -j@THREADS@
]]
	end
	writeln[[
#COPY --from=0 /terra_install/* ./dockerbuild/
]]

	local dockerstring = expand(table.concat(lines))
	local filename = expand("docker/Dockerfile-@DISTRO@-@RELEASE@-@LLVM@-@BUILDSYSTEM@")
	local dockerfile = io.open(filename, "w")

	dockerfile:write(dockerstring)
	dockerfile:close()
end

for _,options in ipairs(argmatrix) do
	createDockerfile(options)
end
