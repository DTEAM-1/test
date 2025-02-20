 
#!/usr/bin/env bash
 
#
 
rp_module_id="borked3ds"
rp_module_desc="3DS Emulator borked3ds"
rp_module_help="ROM Extension: .3ds .3dsx .elf .axf .cci ,cxi .app\n\nCopy your 3DS roms to $romdir/3ds"
rp_module_licence="GPL2 https://github.com/Borked3DS/Borked3DS/blob/master/license.txt"
rp_module_section="exp"
rp_module_flags=" "
 
function depends_borked3ds() {
    if compareVersions $__gcc_version lt 7; then
        md_ret_errors+=("Sorry, you need an OS with gcc 7.0 or newer to compile borked3ds")
        return 1
    fi
 
    # Additional libraries required for running
local depends=(build-essential cmake clang clang-format libc++-dev libsdl2-dev libssl-dev qt6-l10n-tools qt6-tools-dev qt6-tools-dev-tools  qt6-base-dev qt6-base-private-dev libxcb-cursor-dev libvulkan-dev qt6-multimedia-dev libqt6sql6 libqt6core6 libasound2-dev xorg-dev libx11-dev libxext-dev libpipewire-0.3-dev libsndio-dev libfdk-aac-dev ffmpeg libgl-dev libswscale-dev libavformat-dev libavcodec-dev libavdevice-dev libglut3.12 libglut-dev freeglut3-dev mesa-vulkan-drivers libinput-dev) 
 
		getDepends "${depends[@]}"
 
}
 # openssl
function sources_borked3ds() {
    gitPullOrClone "$md_build" https://github.com/rtiangha/Borked3DS.git
}
 
function build_borked3ds() {
    cd "$md_build/borked3ds"
mkdir build
cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
cmake --build . -- -j"$(nproc)"
    md_ret_require="$md_build/build/bin"
 
}
 
function install_borked3ds() {
      md_ret_files=(
      'build/bin/Release/borked3ds'
      #'build/bin/Release/borked3ds-cli'
	  #'build/bin/Release/borked3ds-room'
	  #'build/bin/Release/tests'
 
	        ''
      )
 
}
 
function configure_borked3ds() {
 
    mkRomDir "3ds"
    ensureSystemretroconfig "3ds"
    local launch_prefix
    isPlatform "kms" && launch_prefix="XINIT-WMC:"
	 addEmulator 0 "$md_id-ui" "3ds" "$launch_prefix$md_inst/borked3ds"
	 addEmulator 1 "$md_id-roms" "3ds" "$launch_prefix$md_inst/borked3ds %ROM%"
	#addEmulator 1 "$md_id-room" "3ds" "$launch_prefix$md_inst/borked3ds-room"
	#addEmulator 2 "$md_id-cli" "3ds" "$launch_prefix$md_inst/borked3ds-cli"
	#addEmulator 3 "$md_id-tests" "3ds" "$launch_prefix$md_inst/tests"
    addSystem "3ds" "3ds" ".3ds .3dsx .elf .axf .cci ,cxi .app"
 
 
}
 
