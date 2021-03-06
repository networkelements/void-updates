#!/bin/sh

set -e

init_src() {
  if ! [ -d $src/.git ]; then
    mkdir -p $src
    git clone -q $repo $src
  fi

  if ! [ -d $src/hostdir/binpkgs ]; then
    (cd $src && ./xbps-src binary-bootstrap)
  fi
}

update_src() {
  GIT_WORK_TREE=$src GIT_DIR=$src/.git git pull -q
}

is_meta() {
  (
    cd $src
    ./xbps-src show $1 | grep -q '^build_style:[[:blank:]]*meta$'
  )
}

is_versioned() {
  case $1 in
    *-git) return 1;;
  esac
  return 0
}

find_pkgs() {
  local f p

  for f in $src/srcpkgs/*; do
    p=$(basename $f)

    if [ ! -h $f ] && [ -f $f/template ] && ! is_meta $p && is_versioned $p; then
      printf -- '%s\n' $p
    fi
  done
}

add_maintainer() {
  local p m
  while IFS= read -r p; do
    m=$(grep ^maintainer= $src/srcpkgs/$p/template |
      awk -F'<' '{ print $2 }' |
      tr -d ">\"'" | tr -d ' ')

    if [ "$m" ]; then
      printf '%s %s\n' $p $dest/updates_$m.txt
    fi
  done
}

parallel_check() {
  xargs -P20 -L1 /bin/sh -c \
    "(cd $src && ./xbps-src update-check \$0) >> \$1"
}

create_summary() {
  local d=$(($end - $start))
  local t="Void Updates for $(date +%Y-%m-%d\ %H:%M\ %Z) (took: ${d}s)"
  local f m

  {
    printf '%s\n%s\n\n' "$t" $(printf %${#t}s |tr ' ' =)

    for f in $dest/updates_*.txt; do
      if [ -s $f ]; then
        m=$(basename ${f%%.txt} | sed 's/updates_//')

        printf '%s\n%s\n' $m $(printf %${#m}s |tr ' ' -)
        sort $f
        printf -- '\n'
      else
        rm -f $f
      fi
    done
  } > $dest.txt
}

make_current() {
  ln -sf $dest.txt $out/$name.txt
  ln -sfn $dest $out/$name
}

while getopts "p:r:s:o:" opt; do
  case $opt in
    p)
      procs=$OPTARG
      ;;
    r)
      repo=$OPTARG
      ;;
    s)
      src=$OPTARG
      ;;
    o)
      out=$OPTARG
      ;;
  esac
done

[ "$procs" ] || procs=1
[ "$repo" ]
[ "$src" ]
[ "$out" ]

name=$(basename $0)
date=$(date +%Y-%m-%d)
dest=$out/${name}_$date

mkdir -p $dest

{
  start=$(date +%s)
  init_src
  update_src
  find_pkgs | add_maintainer | parallel_check
  end=$(date +%s)
  create_summary
  make_current
} 2> $dest/_log.txt
