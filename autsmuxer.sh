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
VERSION="4.20103112"

IFS=$'\n'


##


type_allpkgreq () {
for pkg in $pkgreq; do
	! $(type "$pkg" &> "/dev/null") && echo -e "\n $pkg is required." && ((pkgreqcounter++))
done

[ -n "$pkgreqcounter" ] && exit 1
}


##


tsmuxer_mkv2x () {
echo -e " Processng: $input..\n"

mkvinfo=$(mkvinfo "$input")
case $(echo "$mkvinfo" | grep "EBML version:" | cut -d' ' -f4) in
	1) grep_b="-B6"; grep_a="-A8"
	audio_lang="und"; subs_lang="und"
	;;
	*) grep_b="-B11"; grep_a="-A18"
	_extebml="0"
	;;
esac


video_codec=($(echo "$mkvinfo" | egrep -i "+ Codec ID: V_MPEG4/ISO/AVC|V_MS/VFW/WVC1|V_MPEG-2" | cut -d' ' -f6))
video_track=($(echo "$mkvinfo" | grep -i "+ Codec ID: ${video_codec[*]}" "$grep_b" | grep -i "+ Track number:" | cut -d' ' -f6))


audio_codec=($(echo "$mkvinfo" | egrep -i "+ Codec ID: A_AC3|A_AAC|A_DTS|A_MP3|A_MPEG/L2|A_MPEG/L3|A_LPCM" | cut -d' ' -f6))
audio_track=($(echo "$mkvinfo" | grep -i "+ Codec ID: ${audio_codec[*]}" "$grep_b" | grep -i "+ Track number:" | cut -d' ' -f6))
[ -z "$audio_lang" ] && audio_lang=($(echo "$mkvinfo" | grep -i "Track type: audio" -C13 | grep -i "Language:" | cut -d' ' -f5))


subs_format=($(echo "$mkvinfo" | egrep -i "+ Codec ID: S_HDMV/PGS|S_TEXT/UTF8" | cut -d' ' -f6))
subs_track=($(echo "$mkvinfo" | grep -i "+ Codec ID: ${subs_format[*]}" "$grep_b" | grep -i "+ Track number:" | cut -d' ' -f6))
[ -z "$subs_lang" ] && subs_lang=($(echo "$mkvinfo" | grep -i "Track type: subtitles" -C13 | grep -i "Language:" | cut -d' ' -f5))


[ -n "$VTRACK" ] && vid="$((VTRACK-1))" || vid="0"
[ -n "$ATRACK" ] && aud="$((ATRACK-1))" || aud="0"
[ -n "$STRACK" ] && sub="$((STRACK-1))" || sub="0"

[ -f "${input%.*}.meta" ] && rm "${input%.*}.meta"

if [ -n "${video_codec[vid]}" ]; then
	video_fps=$(echo "$mkvinfo" | grep "+ Track number: ${video_track[vid]}" "$grep_a" | grep -i "+ Default duration:" | cut -d' ' -f7 | tr -d '(')

	case "$FORMAT" in
		ts|m2ts) echo -n "MUXOPT --no-pcr-on-video-pid --new-audio-pes --vbr --vbv-len=500" >> "${input%.*}.meta";;
		bluray) echo -n "MUXOPT --no-pcr-on-video-pid --new-audio-pes --blu-ray --vbr --auto-chapters=5 --vbv-len=500" >> "${input%.*}.meta";;
		avchd) echo -n "MUXOPT --no-pcr-on-video-pid --new-audio-pes --avchd --vbr --auto-chapters=5 --vbv-len=500" >> "${input%.*}.meta";;
		demux) echo -n "MUXOPT --no-pcr-on-video-pid --new-audio-pes --demux --vbr --vbv-len=500" >> "${input%.*}.meta";;
	esac
	
	[ -n "$SPLIT" ] && echo -n " --split-size=$SPLIT" >> "${input%.*}.meta"

	case "$_extebml" in
		0) echo -e "\n${video_codec[vid]}, $input, level=4.1, fps=$video_fps, insertSEI, contSPS, track=${video_track[vid]}, lang=${audio_lang[aud]}" >> "${input%.*}.meta"
		;;
		*) mkvextract tracks "$input" "${video_track[vid]}":"${input%.*}.264" && \
		echo -e "\n${video_codec[vid]}, ${input%.*}.264, level=4.1, fps=$video_fps, insertSEI, contSPS, lang=${audio_lang[aud]}" >> "${input%.*}.meta"
		;;
	esac

else
	echo -e "\n Incompatible video codec found."
	exit 1
fi


case "${audio_codec[aud]}" in
	A_DTS)	if [ "$DTS" = "0" ]; then
			mkvextract tracks "$input" "${audio_track[aud]}":"${input%.*}.dts" && dcadec -o wavall "${input%.*}.dts" | aften -v 0 -readtoeof 1 - "${input%.*}.ac3" && \
			echo "A_AC3, ${input%.*}.ac3, lang=${audio_lang[aud]}" >> "${input%.*}.meta"
		else
			case "$_extebml" in
				0) echo "A_DTS, $input, track=${audio_track[aud]}, lang=${audio_lang[aud]}" >> "${input%.*}.meta"
				;;
				*) mkvextract tracks "$input" "${audio_track[aud]}":"${input%.*}.dts" && \
				echo "A_DTS, ${input%.*}.dts, lang=${audio_lang[aud]}" >> "${input%.*}.meta"
				;;
			esac
		fi
	;;
	A_AC3)	_repairac3 () {
			audio_channels=$(echo "$mkvinfo" | grep -i "+ Track number: ${audio_track[aud]}" "$grep_a" | grep -i "+ Channels:" | cut -d' ' -f6)
			audio_frequency=$(echo "$mkvinfo" | grep -i "+ Track number: ${audio_track[aud]}" "$grep_a" | grep -i "+ Sampling frequency:" | cut -d' ' -f7)
			
			##if input headers contain 'Name' tag, mencoder only reads first few MBs. few files will require this (bizarre) fix.
			$(echo "$mkvinfo" | grep -i "+ Track number: ${audio_track[aud]}" "$grep_a" | grep -q "+ Name:") && audio_channels="2"

			case "$audio_channels" in
				2) _aften () { aften -v 1 -raw_ch 2 -raw_sr "$audio_frequency" -b 192 -wmax 30 - "${input%.*}.ac3"; };;
				*) _aften () { aften -v 1 -raw_ch "$audio_channels" -lfe 1 -raw_sr "$audio_frequency" -b 384 -wmax 30 - "${input%.*}.ac3"; };;
			esac
	
			mencoder -noconfig all -msglevel all=-1 -really-quiet -of rawaudio -af format=s16le -lavdopts threads=2 \
			-oac pcm -ovc frameno "$input" -of rawaudio -channels "$audio_channels" -srate "$audio_frequency" -mc 0 -noskip -o - | _aften
	
			echo "A_AC3, ${input%.*}.ac3, lang=${audio_lang[aud]}" >> "${input%.*}.meta"
		}
		
		case "$_extebml" in
			0) _tsmuxerinfo=$(tsMuxeR "$input")
			if ! echo "$_tsmuxerinfo" | grep -s "Track ID:    ${audio_track[aud]}" -A1 | grep -q "Can't detect stream type"; then
				echo "A_AC3, $input, track=${audio_track[aud]}, lang=${audio_lang[aud]}" >> "${input%.*}.meta"
			else
				_repairac3
			fi
			;;
			*) mkvextract tracks "$input" "${audio_track[aud]}":"${input%.*}.ac3" && _tsmuxerinfo=$(tsMuxeR "${input%.*}.ac3")
			if ! echo "$_tsmuxerinfo" | grep -q "Can't detect stream type"; then
				echo "A_AC3, ${input%.*}.ac3, lang=${audio_lang[aud]}" >> "${input%.*}.meta"
			else
				rm "${input%.*}.ac3"
				_repairac3
			fi
			;;
		esac
	;;
	A_MPEG/L[2-3]) 	case "$_extebml" in
				0) echo "A_MP3, $input, track=${audio_track[aud]}, lang=${audio_lang[aud]}" >> "${input%.*}.meta"
				;;
				*) mkvextract tracks "$input" "${audio_track[aud]}":"${input%.*}.mp3" && \
				echo "A_MP3, ${input%.*}.mp3, lang=${audio_lang[aud]}" >> "${input%.*}.meta"
				;;
			esac
	;;
	A_*)	case "$_extebml" in
			0) echo "${audio_codec[aud]}, $input, track=${audio_track[aud]}, lang=${audio_lang[aud]}" >> "${input%.*}.meta"
			;;
			*) mkvextract tracks "$input" "${audio_track[aud]}":"${input%.*}.aud" && \
			echo "${audio_codec[aud]}, ${input%.*}.aud, lang=${audio_lang[aud]}" >> "${input%.*}.meta"
			;;
		esac
	;;
	*) echo -e "\n Incompatible audio codec found."
	exit 1
	;;
esac


if [ -f "$SFONT" -a -n "${subs_format[sub]}" ]; then
	video_width=$(echo "$mkvinfo" | grep "+ Pixel width:" | cut -d':' -f2 | tr -d ' ')
	video_height=$(echo "$mkvinfo" | grep "+ Pixel height:" | cut -d':' -f2 | tr -d ' ')
	
	case "$_extebml" in
			0) subs_source="$input"
			;;
			*) mkvextract tracks "$input" "${subs_track[sub]}":"${input%.*}.sub" && subs_source="${input%.*}.sub"
			;;
	esac
	
	echo "${subs_format[sub]}, $subs_source, font-name=$SFONT, font-size=65, font-color=0x00ffffff, bottom-offset=24, \
	font-border=2, text-align=center, video-width=$video_width, video-height=$video_height, fps=$video_fps, track=${subs_track[sub]}, \
	lang=${subs_lang[sub]}" >> "${input%.*}.meta"
fi

case "$FORMAT" in ts|m2ts) output+=".$FORMAT";; bluray|avchd|demux) output+=".$(echo $FORMAT | tr [:lower:] [:upper:])";; esac

tsMuxeR "${input%.*}.meta" "$output"
[ "$?" != "0" ] && echo -e "\n Error muxing: ${input##*/}." && _notmp && return 1
	
echo -e "\n ${input##*/} successfully remuxed to: $output!"
[ "$SAVE_INPUT" = "0" ] && rm "$input" && _notmp
}

_notmp () {
	for tmp in "${input%.*}.meta" "${input%.*}.264" "${input%.*}.dts" "${input%.*}.ac3" "${input%.*}.mp3" "${input%.*}.aud" "${input%.*}.sub"; do [ -f "$tmp" ] && rm "$tmp"; done
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

pkgreq+=("mkvinfo" "mkvextract" "dcadec" "aften" "mencoder" "tsMuxeR")
type_allpkgreq

if [ "$RECURSIVE" = "1" -a -d "$INPUT" ]; then INPUT=($(find "$INPUT" -type f | egrep -i ".mkv$" | sort))
elif [ -d "$INPUT" ]; then INPUT=($(find "$INPUT" -maxdepth 1 -type f | egrep -i ".mkv$" | sort))
elif [ ! -f "$INPUT" ]; then echo -e "\n Input file: $input not found." && usage; fi

for input in ${INPUT[*]}; do output="${input%.*}"; tsmuxer_mkv2x; done


