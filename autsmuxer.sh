#!/bin/bash
#
# autsmuxer - automated tsMuxeR frontend. (MKV input.)
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of the GNU Library General Public License as published
# by the Free Software Foundation; either version 2, or (at your option)
# any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#


##options##
RECURSIVE="0" ##recurse when provided with directory input.
SAVE_INPUT="1" ##set to 1 to retain MKV input files.
FORMAT="m2ts" ##available: ts, m2ts, bluray, avchd, demux
DTS="0" ## set to 1 to never transcode DTS.
VTRACK="" ##specify video track.
ATRACK="" ##specify audio track.
STRACK="" ##specify subs track.
SFONT="/usr/share/fonts/TTF/DejaVuSans.ttf" ##required only for subs.
SPLIT="" ##maximum filesize per part. eg. 4000MB (safer with 3900) for FAT32 filesystem.


##


TITLE="autsmuxer"
VERSION="4.20101402"

IFS=$'\n'


##


type_allpkgreq () {
for pkg in $@; do
	! $(type "$pkg" &> "/dev/null") && { echo -e "\n $pkg is required."; ((pkgreqcounter++)); }
done

[ -n "$pkgreqcounter" ] && die
}


##


tsmuxer_mkv2x () {
echo -e " Processng: $1..\n"

mkvinfo=$(mkvinfo "$1")
case $(echo "$mkvinfo" | grep "EBML version:" | cut -d' ' -f4) in
	1) _grepb="-B6"; _grepa="-A8"
	audio_lang="und"; subs_lang="und"
	;;
	*) _grepb="-B11"; _grepa="-A18"
	_extebml="0"
	;;
esac


video_codec=($(echo "$mkvinfo" | egrep -i "+ Codec ID: V_MPEG4/ISO/AVC|V_MS/VFW/WVC1|V_MPEG-2" | cut -d' ' -f6))
video_track=($(echo "$mkvinfo" | grep -i "+ Codec ID: ${video_codec[@]}" "$_grepb" | grep -i "+ Track number:" | cut -d' ' -f6))


audio_codec=($(echo "$mkvinfo" | egrep -i "+ Codec ID: A_AC3|A_AAC|A_DTS|A_MP3|A_MPEG/L2|A_MPEG/L3|A_LPCM" | cut -d' ' -f6))
audio_track=($(echo "$mkvinfo" | grep -i "+ Codec ID: ${audio_codec[@]}" "$_grepb" | grep -i "+ Track number:" | cut -d' ' -f6))
[ -z "$audio_lang" ] && audio_lang=($(echo "$mkvinfo" | grep -i "Track type: audio" -C13 | grep -i "Language:" | cut -d' ' -f5))


subs_format=($(echo "$mkvinfo" | egrep -i "+ Codec ID: S_HDMV/PGS|S_TEXT/UTF8" | cut -d' ' -f6))
subs_track=($(echo "$mkvinfo" | grep -i "+ Codec ID: ${subs_format[@]}" "$_grepb" | grep -i "+ Track number:" | cut -d' ' -f6))
[ -z "$subs_lang" ] && subs_lang=($(echo "$mkvinfo" | grep -i "Track type: subtitles" -C13 | grep -i "Language:" | cut -d' ' -f5))


[ -n "$VTRACK" ] && vid="$((VTRACK-1))" || vid="0"
[ -n "$ATRACK" ] && aud="$((ATRACK-1))" || aud="0"
[ -n "$STRACK" ] && sub="$((STRACK-1))" || sub="0"

[ -f "${1%.*}.meta" ] && rm "${1%.*}.meta"

if [ -n "${video_codec[vid]}" ]; then
	video_fps=$(echo "$mkvinfo" | grep "+ Track number: ${video_track[vid]}" "$_grepa" | grep -i "+ Default duration:" | cut -d' ' -f7 | tr -d '(')

	case "$FORMAT" in
		ts|m2ts) echo -n "MUXOPT --no-pcr-on-video-pid --new-audio-pes --vbr --vbv-len=500" >> "${1%.*}.meta";;
		bluray) echo -n "MUXOPT --no-pcr-on-video-pid --new-audio-pes --blu-ray --vbr --auto-chapters=5 --vbv-len=500" >> "${1%.*}.meta";;
		avchd) echo -n "MUXOPT --no-pcr-on-video-pid --new-audio-pes --avchd --vbr --auto-chapters=5 --vbv-len=500" >> "${1%.*}.meta";;
		demux) echo -n "MUXOPT --no-pcr-on-video-pid --new-audio-pes --demux --vbr --vbv-len=500" >> "${1%.*}.meta";;
	esac
	
	[ -n "$SPLIT" ] && echo -n " --split-size=$SPLIT" >> "${1%.*}.meta"

	case "$_extebml" in
		0) echo -e "\n${video_codec[vid]}, $1, level=4.1, fps=$video_fps, insertSEI, contSPS, track=${video_track[vid]}, lang=${audio_lang[aud]}" >> "${1%.*}.meta"
		;;
		*) mkvextract tracks "$1" "${video_track[vid]}":"${1%.*}.264" && \
		echo -e "\n${video_codec[vid]}, ${1%.*}.264, level=4.1, fps=$video_fps, insertSEI, contSPS, lang=${audio_lang[aud]}" >> "${1%.*}.meta"
		;;
	esac

else
	die "\n Incompatible video codec found."
fi


case "${audio_codec[aud]}" in
	A_DTS)	if [ "$DTS" = "0" ]; then
			mkvextract tracks "$1" "${audio_track[aud]}":"${1%.*}.dts" && dcadec -o wavall "${1%.*}.dts" | aften -v 0 -readtoeof 1 - "${1%.*}.ac3" && \
			echo "A_AC3, ${1%.*}.ac3, lang=${audio_lang[aud]}" >> "${1%.*}.meta"
		else
			case "$_extebml" in
				0) echo "A_DTS, $1, track=${audio_track[aud]}, lang=${audio_lang[aud]}" >> "${1%.*}.meta"
				;;
				*) mkvextract tracks "$1" "${audio_track[aud]}":"${1%.*}.dts" && \
				echo "A_DTS, ${1%.*}.dts, lang=${audio_lang[aud]}" >> "${1%.*}.meta"
				;;
			esac
		fi
	;;
	A_AC3)	_repairac3 () {
			audio_channels=$(echo "$mkvinfo" | grep -i "+ Track number: ${audio_track[aud]}" "$_grepa" | grep -i "+ Channels:" | cut -d' ' -f6)
			audio_frequency=$(echo "$mkvinfo" | grep -i "+ Track number: ${audio_track[aud]}" "$_grepa" | grep -i "+ Sampling frequency:" | cut -d' ' -f7)
			
			##if input headers contain 'Name' tag, mencoder only reads first few MBs. few files will require this (bizarre) fix.
			$(echo "$mkvinfo" | grep -i "+ Track number: ${audio_track[aud]}" "$_grepa" | grep -q "+ Name:") && audio_channels="2"

			case "$audio_channels" in
				2) _aften () { aften -v 1 -raw_ch 2 -raw_sr "$audio_frequency" -b 192 -wmax 30 - "${1%.*}.ac3"; };;
				*) _aften () { aften -v 1 -raw_ch "$audio_channels" -lfe 1 -raw_sr "$audio_frequency" -b 384 -wmax 30 - "${1%.*}.ac3"; };;
			esac
	
			mencoder -noconfig all -msglevel all=-1 -really-quiet -of rawaudio -af format=s16le -lavdopts threads=2 \
			-oac pcm -ovc frameno "$1" -of rawaudio -channels "$audio_channels" -srate "$audio_frequency" -mc 0 -noskip -o - | _aften
	
			echo "A_AC3, ${1%.*}.ac3, lang=${audio_lang[aud]}" >> "${1%.*}.meta"
		}
		
		case "$_extebml" in
			0) _tsmuxerinfo=$(tsMuxeR "$1")
			if ! echo "$_tsmuxerinfo" | grep -s "Track ID:    ${audio_track[aud]}" -A1 | grep -q "Can't detect stream type"; then
				echo "A_AC3, $1, track=${audio_track[aud]}, lang=${audio_lang[aud]}" >> "${1%.*}.meta"
			else
				_repairac3
			fi
			;;
			*) mkvextract tracks "$1" "${audio_track[aud]}":"${1%.*}.ac3" && _tsmuxerinfo=$(tsMuxeR "${1%.*}.ac3")
			if ! echo "$_tsmuxerinfo" | grep -q "Can't detect stream type"; then
				echo "A_AC3, ${1%.*}.ac3, lang=${audio_lang[aud]}" >> "${1%.*}.meta"
			else
				rm "${1%.*}.ac3"
				_repairac3
			fi
			;;
		esac
	;;
	A_MPEG/L[2-3]) 	case "$_extebml" in
				0) echo "A_MP3, $1, track=${audio_track[aud]}, lang=${audio_lang[aud]}" >> "${1%.*}.meta"
				;;
				*) mkvextract tracks "$1" "${audio_track[aud]}":"${1%.*}.mp3" && \
				echo "A_MP3, ${1%.*}.mp3, lang=${audio_lang[aud]}" >> "${1%.*}.meta"
				;;
			esac
	;;
	A_*)	case "$_extebml" in
			0) echo "${audio_codec[aud]}, $1, track=${audio_track[aud]}, lang=${audio_lang[aud]}" >> "${1%.*}.meta"
			;;
			*) mkvextract tracks "$1" "${audio_track[aud]}":"${1%.*}.aud" && \
			echo "${audio_codec[aud]}, ${1%.*}.aud, lang=${audio_lang[aud]}" >> "${1%.*}.meta"
			;;
		esac
	;;
	*) die "\n Incompatible audio codec found."
	;;
esac


if [ -f "$SFONT" -a -n "${subs_format[sub]}" ]; then
	video_width=$(echo "$mkvinfo" | grep "+ Pixel width:" | cut -d':' -f2 | tr -d ' ')
	video_height=$(echo "$mkvinfo" | grep "+ Pixel height:" | cut -d':' -f2 | tr -d ' ')
	
	case "$_extebml" in
			0) subs_source="$1"
			;;
			*) mkvextract tracks "$1" "${subs_track[sub]}":"${1%.*}.sub" && subs_source="${1%.*}.sub"
			;;
	esac
	
	echo "${subs_format[sub]}, $subs_source, font-name=$SFONT, font-size=65, font-color=0x00ffffff, bottom-offset=24, \
	font-border=2, text-align=center, video-width=$video_width, video-height=$video_height, fps=$video_fps, track=${subs_track[sub]}, \
	lang=${subs_lang[sub]}" >> "${1%.*}.meta"
fi

output="$2"
case "$FORMAT" in ts|m2ts) output+=".$FORMAT";; bluray|avchd|demux) output+=".$(echo $FORMAT | tr [:lower:] [:upper:])";; esac

tsMuxeR "${1%.*}.meta" "$output" || die "\n Error muxing: ${1##*/}."

echo -e "\n ${1##*/} successfully remuxed to: $output!"
[ "$SAVE_INPUT" = "0" ] && rm -f "$1"

for tmp in "${1%.*}."{meta,264,dts,ac3,mp3,aud,sub}; do [ -f "$tmp" ] && rm -f "$tmp"; done

return 0
}


die() {
echo -e "$1"
exit 1
}


##


usage () {
echo -e "\n $TITLE - $VERSION"
echo -e '\nusage: '${0##*/}' [-options] inputfile/dir.'
echo -e '\noptions:'
echo -e '\n\t-R\t- Recursively search for MKV files.'
echo -e '\n\t-d\t- Delete input file after successful mux.'
echo -e '\n\t--recursive <0/1>\n\t--save-input <0/1>\n\t--format <ts/m2ts/bluray/avchd/demux>\n\t--dts <0/1>\n\t--vtrack <#>\n\t--atrack <#>\n\t--strack <#>\n\t--sfont </path/to/font.ttf>\n\t--split <#MB/GB>'
exit 0
}


##


while [ "$#" -ne "0" ]; do
	case $1 in
		--recursive)
		shift; RECURSIVE="$1"
		[ -z "$1" -o "$1" -ge "2" ] && echo -e "\n RECURSIVE must be 1 or 0." && exit 1
		;;
		--save-input)
		shift; SAVE_INPUT="$1"
		[ -z "$1" -o "$1" -ge "2" ] && echo -e "\n SAVE_INPUT must be 1 or 0." && exit 1
		;;
		--format)
		shift; [[ $(echo "$1" | egrep -o "ts|m2ts|bluray|avchd|demux") ]] && FORMAT="$1"
		;;
		--dts)
		shift; DTS="$1"
		[ -z "$1" -o "$1" -ge "2" ] && echo -e "\n DTS must be 1 or 0." && exit 1
		;;
		--vtrack)
		shift; VTRACK=$(echo "$1" | tr -d '[:alpha:]')
		[ -z "$1" -o "$1" = "0" ] && echo -e "\n VTRACK track must be >1." && exit 1
		;;
		--atrack)
		shift; ATRACK=$(echo "$1" | tr -d '[:alpha:]')
		[ -z "$1" -o "$1" = "0" ] && echo -e "\n ATRACK track must be >1." && exit 1
		;;
		--strack)
		shift; STRACK=$(echo "$1" | tr -d '[:alpha:]')
		[ -z "$1" -o "$1" = "0" ] && echo -e "\n STRACK track must be >1." && exit 1
		;;
		--sfont)
		shift; SFONT="$1"
		[ ! -f "$SFONT" ] && echo -e "\n $SFONT not found." && exit 1
		;;
		--split)
		shift; SPLIT="$1"
		[ -z "$1" -o "$1" = "0" ] && echo -e "\n SPLIT must be >1." && exit 1
		;;
		-*)
		while getopts ":hRd" opt $1; do
		case "$opt" in
			h)
			usage
			exit 0
			;;
			R)
			RECURSIVE="1"
			;;
			d)
			SAVE_INPUT="0"
			;;
		esac
		done
		;;
		*) INPUT=("$1")
		;;
	esac
	shift
done

type_allpkgreq "mkvinfo" "mkvextract" "dcadec" "aften" "mencoder" "tsMuxeR"

if [ "$RECURSIVE" = "1" -a -d "$INPUT" ]; then INPUT=($(find "$INPUT" -type f | egrep -i "\.mkv$" | sort))
elif [ -d "$INPUT" ]; then INPUT=($(find "$INPUT" -maxdepth 1 -type f | egrep -i "\.mkv$" | sort))
elif [ ! -f "$INPUT" ]; then echo -e "\n Input file: $INPUT not found." && usage; fi

for input in ${INPUT[@]}; do tsmuxer_mkv2x "$input" "${input%.*}"; done


