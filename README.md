# Chiptune MPD setup

The MPD available in homebrew does not have an option for adding support for
the Game Music Emu library.

Additionally, the `libgme` packaged by most distros is from Michael
Pyne's fork (https://bitbucket.org/mpyne/game-music-emu/wiki/Home) - but
Christopher Snowhill has an updated fork (which is what the Foobar2k
plugin uses) here: https://bitbucket.org/losnoco/game_music_emu

These are instructions and patches to:

1. Install Christopher's libgme fork
2. Patch MPD's source to use that fork
3. Additional "nice-to-have" MPD patches (load M3U sidecars, for example)

## Dependencies

You'll need cmake and zlib for libgme. For MPD, you'll need whatever other
libraries you want to use (ffmpeg, libsidplayfp, etc).

## Build libgme

I like to use "stow" to have a Homebrew-ish system for locally-built packages.

If you don't want to use stow, then just remote DESTDIR and install straight
to /usr/local.

```bash
# todo: update this if/when changes get merged into Christopher's fork
$ git clone -b add-cmakelists --recursive https://jprjr@bitbucket.org/jprjr/game_music_emu.git
$ cd game_music_emu
$ mkdir build
$ cd build
$ cmake -DCMAKE_INSTALL_PREFIX=/usr/local -DCMAKE_BUILD_TYPE=Release ..
$ make
$ make install DESTDIR=/usr/local/stow/libgme-0.7.0
$ mv /usr/local/stow/libgme-0.7.0/usr/local/* /usr/local/stow/libgme-0.7.0
$ rm -rf /usr/local/stow/libgme-0.7.0/usr
$ cd /usr/local/stow
$ stow libgme-0.7.0
```

## Patch MPD

I have included patches for MPD in the patches folder - the first patch
is the only required patch, the rest are optional (but nice to have).


* `0001-GME-Plugin-work-with-Kode54-s-fork.patch`
    * Required.
* `0002-GME-Plugin-load-sidecar-m3u-files.patch`
    * Loads .m3u files for more/richer metadata. The M3U needs to have the same basename as the chiptune file.
    * For example, if you have "Mario.nsf", you'll want "Mario.m3u" in the same folder
* `0003-GME-Plugin-fix-track-lengths.patch`
    * Fixes track lengths (by default they're all 8 seconds off)
* `0004-GME-Plugin-remove-001-999-from-track-titles.patch`
    * This removes adding "001/999" to the track title in multi-track chiptune files.
* `0005-GME-Plugin-add-sgc-file-support.patch`
    * Allows loading ".sgc" files

Then just configure and install normally. Below is an example of
compiling for OSX, tweak to suit your needs. The important part
is `--enable-gme`

You'll want MPD > 0.20.11 - before that, there's a bug with chiptune track numbering.

Some more recommendations:

Install libsidplayfp and add `--enable-sidplay` for Commodore 64 support (https://sourceforge.net/projects/sidplay-residfp/)

```bash
$ wget https://www.musicpd.org/download/mpd/0.20/mpd-0.20.21.tar.xz
$ tar xf mpd-0.20.21.tar.xz
$ cd mpd-0.20.21
$ for p in /path/to/patches/* ; do \
  patch -p1 -i "${p}" ; \
done
$ ./configure \
  --disable-debug \
  --disable-dependency-tracking \
  --prefix=/usr/local \
  --sysconfdir=/etc \
  --disable-libwrap \
  --disable-mad \
  --disable-mpc \
  --disable-soundcloud \
  --enable-ao \
  --enable-bzip2 \
  --enable-expat \
  --enable-ffmpeg \
  --enable-fluidsynth \
  --enable-osx \
  --enable-upnp \
  --enable-vorbis-encoder \
  --enable-gme
$ make
$ make install DESTDIR=/usr/local/stow/mpd-0.20.21
$ mv /usr/local/stow/mpd-0.20.21/usr/local/* /usr/local/stow/mpd-0.20.21/
$ rm -rf /usr/local/stow/mpd-0.20.21/usr
$ cd /usr/local/stow
$ stow mpd-0.20.21
```

## M3U sidecar files

A lot of chiptunes are distributed with split M3U files - each track has its own file.

Additionally, they often have extra data in the "title" field, like artist, game, etc.

Here's a typical example:

```
G-3321.kss::KSS,7,Title Screen - Masafumi Ogata - Sonic the Hedgehog 2 - ©1992-11-21 Aspect\, Sega,0:20,,1
```

My patch to MPD just looks for a single M3U file - so I have a script to join M3U files.
It also tries to strip out that extra metadata by finding the longest common string.
This works *most* of the time, but you should always double-check and edit the generated
M3U file.

Assuming you have a folder like:

```
sonic2/
├── 01 Title Screen.m3u
├── 02 Act Start.m3u
├── 03 Underground Zone.m3u
├── 04 Act Complete.m3u
├── 05 Found Emerald!.m3u
├── 06 Invincible.m3u
├── 07 Boss Theme.m3u
├── 08 Sky High Zone.m3u
├── 09 Aqua Lake Zone.m3u
├── 10 Green Hills Zone.m3u
├── 11 Gimmick Mountain Zone.m3u
├── 12 Scrambled Egg Zone.m3u
├── 13 Crystal Egg Zone.m3u
├── 14 Bad Ending.m3u
├── 15 Good Ending.m3u
├── 16 The End.m3u
├── 17 Death.m3u
├── 18 Game Over.m3u
├── 19 Continue Screen.m3u
└── G-3321.kss
```

You'll be able to use the script like so:

```bash
$ perl scripts/fixup-m3u.pl sonic2
```

It will:

1. Try to find the chiptune file.
2. If possible, extract embedded metadata (title, artist) from the file.
3. Load up all M3U playlists.
4. Convert the playlist to hex notation for track numbers.
5. Try to remove useless info from track titles.
6. Prompt for game title and composer information.

Here's an example run:

```bash
$ perl scripts/fixup-m3u.pl sonic2
Unable to detect title
Please enter one, or hit return to leave empty: Sonic the Hedgehog 2
Setting title to: Sonic the Hedgehog 2
Unable to detect artist
Please enter one, or hit return to leave empty: Naofumi Hataya, Masafumi Ogata
Setting artist to: Naofumi Hataya, Masafumi Ogata
Writing out playlist file G-3321.m3u
```

After running the script, here's my single-file M3U.

You'll notice the title field isn't quite right, because the artists differed
on some lines, so finding the longest common string didn't remove everything.

```
# Sonic the Hedgehog 2
# Composer: Naofumi Hataya, Masafumi Ogata
G-3321.kss::KSS,$07,Title Screen - Masafumi Ogat,0:20,,0:01
G-3321.kss::KSS,$10,Act Start - Naofumi Hatay,0:03,,0:01
G-3321.kss::KSS,$01,Underground Zone - Tomonori Sawad,2:59,,0:10
G-3321.kss::KSS,$09,Act Complete - Naofumi Hatay,0:04,,0:01
G-3321.kss::KSS,$0C,Found Emerald! - Masafumi Ogat,0:03,,0:01
G-3321.kss::KSS,$08,Invincible - Masafumi Ogat,0:39,,0:10
G-3321.kss::KSS,$11,Boss Theme - Naofumi Hatay,1:55,,0:10
G-3321.kss::KSS,$05,Sky High Zone - Naofumi Hatay,1:36,,0:10
G-3321.kss::KSS,$00,Aqua Lake Zone - Naofumi Hatay,3:13,,0:10
G-3321.kss::KSS,$04,Green Hills Zone - Masafumi Ogat,2:14,,0:10
G-3321.kss::KSS,$02,Gimmick Mountain Zone - Masafumi Ogat,2:42,,0:10
G-3321.kss::KSS,$06,Scrambled Egg Zone - Naofumi Hatay,2:01,,0:10
G-3321.kss::KSS,$03,Crystal Egg Zone - Masafumi Ogat,2:08,,0:10
G-3321.kss::KSS,$0E,Bad Ending - Masafumi Ogat,2:19,,0:01
G-3321.kss::KSS,$12,Good Ending - Masafumi Ogat,2:19,,0:01
G-3321.kss::KSS,$0F,The End - Masafumi Ogata\, Naofumi Hatay,0:04,,0:01
G-3321.kss::KSS,$0A,Death - Masafumi Ogat,0:04,,0:01
G-3321.kss::KSS,$0D,Game Over - Masafumi Ogat,0:06,,0:01
G-3321.kss::KSS,$0B,Continue Screen - Masafumi Ogat,0:17,,0:01
```


