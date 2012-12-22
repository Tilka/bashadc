#!/bin/bash
#
# Copyright 2012 Tillmann Karras <tilkax@gmail.com>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
#
# bashadc 0.815
#
# An ADC (Advanced Direct Connect) client in bash. Yes, I was bored...
# It works by leaving out everything that would be difficult in bash, e.g.:
# - anything that really requires Base32 or Tiger
# - detecting share changes at runtime
# - active mode
# - slot restrictions
# - TLS encryption
# Features which I think should be possible:
# - downloading
# - private messages
#
# Bugs? In my bash script? It's more likely than you think.
#
# Dependencies:
# - bash >= 4.1
# - coreutils (stat, cat, {base,dir}name)
# - bzip2
# - tthsum

# FIXME: the incorrectness of this should set your standards for the rest of the program
escape()  { echo "${1// /\\s}";}
unescape(){ echo "${1//\\s/ }";}

declare -A my
my[share]="$(dirname "$0")/share"
# TODO: implement this setting
my[follow_symlinks]=1
my[hub]=m0nster.c0k.de
my[port]=1511
my[cid]=ZI4ZIM5EFHHL5UN3AGUCZY7OHSPDVQL6WBTNBGI
my[pid]=V7C6LPQ56U7I6FR5GZX6T2Q2QUT35QXGRPIZ7OY
my[nick]='Tilka'
my[description]=$(escape "don't mind me, I'm just a bash script")
# TODO: don't calc share size when this is not -1
my[share_size]=-1
# only used for INF, slots are not actually limited:
my[slots]=2
my[hubs_normal]=1
my[hubs_registered]=0
my[hubs_operator]=0
my[application]=bashadc
my[version]=0.815
my[features]='ADBASE ADTIGR ADPING'
my[filelist_name]=files.xml.bz2
my[filelist_path]="${XDG_CACHE_HOME:-.}/${my[filelist_name]}"

declare -A color
color[normal]="\e[0m"
color[time]="\e[1;30m"
color[highlight]="\e[1;37m"

declare -A errors
errors[00]='generic'
errors[10]='generic hub error'
errors[11]='hub full'
errors[12]='hub disabled'
errors[20]='generic login/access error'
errors[21]='nick invalid'
errors[22]='nick taken'
errors[23]='invalid password'
errors[24]='CID taken'
errors[25]='access denied'
errors[26]='registered users only'
errors[27]='invalid PID supplied'
errors[30]='kicks/bans/disconnects generic'
errors[31]='permanently banned'
errors[32]='temporarily banned'
errors[40]='protocol error'
errors[41]='transfer protocol unsupported'
errors[42]='direct connection failed'
errors[43]='required INF field missing'
errors[44]='invalid state'
errors[45]='required feature missing'
errors[46]='invalid IP supplied in INF'
errors[47]='no hash support overlap in SUP between client and hub'
errors[50]='client-cliet / file transfer error'
errors[51]='file not available'
errors[52]='file part not available'
errors[53]='slots full'
errors[54]='no hash support overlap in SUP between clients'

declare -A files

contains_files() {
	local dir="$1"
	# FIXME: shouldn't trust the link count
	[[ $(stat -c%h "$dir") == "2" ]]
}

recurse_dir() {
	local dir="$1"
	local indent="$2"
	for path in "$dir"/*
	do
		if [ -d "$path" ]
		then
			emit_dir "$path" "$indent"
		# TODO: symlinks
		elif [ -f "$path" ]
		then
			emit_file "$path" "$indent"
		else
			echo "$indent<!-- ignoring $dir -->"
		fi
	done
}

emit_dir() {
	local path="$1"
	local indent="$2"
	# FIXME: escape xml meta chars (e.g. quotes)
	local name="$(basename "$path")"
	if contains_files "$path"
	then
		echo "$indent<Directory Name=\"$name\">"
		recurse_dir "$path" "$ident  "
		echo "$indent</Directory>"
	else
		echo "$indent<Directory Name=\"$name\" />"
	fi
}

emit_file() {
	local file="$1"
	local name="$(basename "$file")"
	local size=$(stat -c%s "$file")
	local tth="$(tthsum "$file")"
	files[$tth]="$file"
	echo "$2<File Name=\"$name\" Size=\"$size\" TTH=\"${tth:0:39}\" />"
}

emit_filelist() {
	echo '<?xml version="1.0" encoding="utf-8" standalone="yes"?>'
	echo "<FileListing Version=\"1\" CID=\"${my[cid]}\" Generator=\"${my[application]} ${my[version]}\" Base=\"/\">"
	shopt -s nullglob
	recurse_dir "${my[share]}" "  "
	echo '</FileListing>'
}

generate_filelist() {
	show "Generating file list of \"${my[share]}\". Please wait..."
	emit_filelist | bzip2 >"${my[filelist_path]}"
	# TODO: symlinks
	my[share_size]=$(find "${my[share]}" -type f -printf "%s\n" | { declare -i total=0; while read size; do total+=size; done; echo $total; })
	show "Done. Share size is ${my[share_size]} bytes."
}

ident2path() {
	local identifier="$1"
	if [[ $identifier == "${my[filelist_name]}" ]]
	then
		path="${my[filelist_name]}"
	else
		regex='TTH/([A-Z2-7]{39})'
		[[ $identifier =~ $regex ]] || show "ERROR: invalid TTH" && return 1
		tth=${BASH_REMATCH[1]}
		path="${files[$tth]}"
		[[ $path == "" ]] && show "ERROR: TTH not found" && return 1
	fi
	echo "$path"
}

show() {
	# FIXME: -e is a dirty hack to avoid having to unescape \n and \\
	echo -e "${color[time]}$(date +%T)${color[normal]} $1" >&2
}

network() {
	declare -A nicks
	declare -A addrs

	server="$1"
	if [ $server ]
	then
		port="$2"
		token="$3"
		show "Connecting to $server:$port..."
		exec {socket}<>/dev/tcp/$server/$port || return
		send() {
			echo "$1" >&$socket
		}
		send "CSUP ${my[features]}"
		send "CINF ID${my[cid]} TO$token"
	else
		send "HSUP ${my[features]}"
		socket=$hub_socket
	fi

	sid2nick() {
		echo "${nicks[$1]}"
	}

	sid2addr() {
		echo ${addrs[$1]}
	}

	field() {
		local fields="$1"
		local prefix="$2"
		for val in $fields
		do
			[ "${val:0:2}" == "$prefix" ] && echo "$(unescape ${val:2})" && return
		done
		return 1
	}

	while read -ru$socket
	do
		line="$REPLY"
		msg_type=${line:0:1}
		cmd=${line:1:3}
		rest="${line:5}"
		case $msg_type in
			[BFU])
				sid1=${rest:0:4}
				rest="${rest:5}"
				;;
			[DE])
				sid1=${rest:0:4}
				sid2=${rest:5:4}
				rest="${rest:10}"
				;;
			I)
				sid1=_HUB
				;;
			[CH])
				# nothing to do here
				;;
			*)
				show "ERROR: unknown message type in line \"$line\""
				continue
				;;
		esac
		case $cmd in
			INF)
				[[ $server ]] && continue
				if test ${nicks[$sid1]+_}
				then
					# TODO: an update, ignore for now
					true
				else
					nick=$(field "$rest" NI)
					addr=$(field "$rest" I4)
					[[ $my_inf_came ]] && show "$nick joined"
					nicks[$sid1]="$nick"
					addrs[$sid1]="$addr"
				fi
				if [ "$sid1" == "${my[sid]}" ]
				then
					my_inf_came=yup
					show "$((${#nicks[*]}-2)) other user(s) online"
				fi
				;;
			QUI)
				sid1=${rest:0:4}
				rest="${rest:5}"
				nick="$(sid2nick $sid1)"
				[[ "$nick" == "" ]] || show "$nick quit"
				unset nicks[$sid1]
				;;
			MSG)
				wire_msg=${rest%% *}
				msg="$(unescape $wire_msg)"
				rest="${rest:$((${#wire_msg}+1))}"
				nick=$(sid2nick $sid1)
				[[ $nick == "${my[nick]}"   ]] && nick="${color[highlight]}$nick${color[normal]}"
				[[ $msg  == *"${my[nick]}"* ]] && nick="${color[highlight]}$nick${color[normal]}"
				pm=$(field "$rest" PM)
				pm="${pm:+${color[highlight]}PM:${color[normal]} }"
				if [[ $(field "$rest" ME) == "1" ]]
				then
					show "$pm** $nick $msg"
				else
					show "$pm<$nick> $msg"
				fi
				;;
			CTM)
				regex='([^ ]*) ([^ ]*) ([^ ]*)'
				[[ $rest =~ $regex ]] || continue
				proto=${BASH_REMATCH[1]}
				port=${BASH_REMATCH[2]}
				token=${BASH_REMATCH[3]}
				rest="${BASH_REMATCH[5]}"
				addr=$(sid2addr $sid1)
				[[ $proto == "ADC/1.0" ]] || continue
				network $addr $port $token &
				;;
			SID)
				my[sid]=${rest:0:4}
				nicks[${my[sid]}]=${my[nick]}
				send "BINF ${my[sid]} ID${my[cid]} PD${my[pid]} NI${my[nick]} DE${my[description]} SS${my[share_size]} SL${my[slots]} HN${my[hubs_normal]} HR${my[hubs_registered]} HO${my[hubs_operator]} AP${my[application]} VE${my[version]}"
				echo "${my[sid]}" >$ipc_fifo
				;;
			GET)
				regex='([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*)( (.*))?'
				[[ $rest =~ $regex ]] || continue
				namespace="${BASH_REMATCH[1]}"
				identifier="${BASH_REMATCH[2]}"
				pos="${BASH_REMATCH[3]}"
				count="${BASH_REMATCH[4]}"
				rest="${BASH_REMATCH[6]}"
				# TODO: send STA on error
				[[ $namespace == "file" ]] || continue
				# TODO: partial file transfers
				[[ $pos == "0" ]] || continue
				path="$(ident2path $identifier)" || continue
				size=$(stat -c%s "$path")
				[ "$count" == "-1" -o "$count" == "$size" ] || continue
				send "CSND file $identifier 0 $size"
				show "Uploading $path..."
				cat "$path" >&$socket
				show "Upload complete."
				;;
			STA)
				regex='(.)(..) ([^ ]+)( (.*))?'
				[[ $rest =~ $regex ]] || continue
				severities=("success" "recoverable error" "fatal error")
				severity=${severities[${BASH_REMATCH[1]}]}
				error=${errors[${BASH_REMATCH[2]}]}
				description="$(unescape "${BASH_REMATCH[3]}")"
				rest=${BASH_REMATCH[5]}
				show "Status: severity=\"$severity\" error=\"$error\" description=\"$description\" other=\"$rest\""
				;;
			SCH|SUP)
				# ignored
				;;
			*)
				show "ERROR: unknown message in line \"$line\""
				;;
		esac
	done
	show "Connection closed."
}

user_input() {
	read -r my_sid <"$ipc_fifo"
	my[sid]=$my_sid
	show "Connected. Your session ID is ${my[sid]}."

	say() {
		send "BMSG ${my[sid]} $(escape "$1") $2"
	}

	while read -er
	do
		case "$REPLY" in
			'')
				# ignore
				;;
			'/say '*)
				send "BMSG ${my[sid]} $(escape "${REPLY/#\/say /}")"
				;;
			'/me '*)
				send "BMSG ${my[sid]} $(escape "${REPLY/#\/me /}") ME1"
				;;
			'/pm '*)
				target=AAAA
				msg=$(escape "${REPLY/#\/pm /}")
				send "EMSG ${my[sid]} $target $msg PM${my[sid]}"
				;;
			'/raw '*)
				send "${REPLY/#\/raw /}"
				;;
			/quit)
				break
				;;
			/help)
				show "Available commands:\n\t/say <msg>\n\t/me <msg>\n\t/pm <nick> <msg>\n\t/raw <adc msg>\n\t/quit\n\t/help"
				;;
			*)
				show "ERROR: unknown command"
				;;
		esac
	done
}

# TODO: detect file changes. for now, just regenerate the file list at every start:
generate_filelist

ipc_fifo="/tmp/${my[application]}-$$.fifo"
mkfifo "$ipc_fifo"

show "Connecting to adc://${my[hub]}:${my[port]}..."
exec {hub_socket}<>/dev/tcp/${my[hub]}/${my[port]} || exit
send() {
	echo "$1" >&$hub_socket
}

cleanup() {
	show "Shutting down..."
	kill %network
	exec 3>&-
	rm "$ipc_fifo"
	trap EXIT
}
trap cleanup EXIT

network &
user_input
