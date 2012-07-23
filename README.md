autsmuxer
=====

mkv2vob CLI clone for *nix.

## dependencies:

* [libdca][libdca]
* [mkvtoolnix][mkvtoolnix]
* [mencoder][mencoder]
* [aften][aften]
* [tsMuxeR][tsmuxer]
* [spdifconvert][spdifconvert]

## usage:

* Install all dependencies, ensuring they are in $PATH.
* bash autsmuxer.sh [-options] inputfile/dir.

## notes:

* mkvtoolnix must be >5.4.0. ([issue 3])
* DTS audio is converted to AC3 unless '--dts 1' is passed.

[libdca]: http://www.videolan.org/developers/libdca.html
[mkvtoolnix]: http://www.bunkus.org/videotools/mkvtoolnix/index.html
[mencoder]: http://www.mplayerhq.hu/
[aften]: http://aften.sourceforge.net/
[tsmuxer]: http://www.smlabs.net/tsmuxer_en.html
[spdifconvert]: http://forums.slimdevices.com/showthread.php?t=19260
[issue 3]: https://github.com/dryes/autsmuxer/issues/3