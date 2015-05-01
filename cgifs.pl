#!/usr/bin/perl

use strict;
use warnings;
use Fuse;
use Getopt::Long;
use POSIX qw(ceil ENOENT ENOTDIR O_WRONLY setsid);
use Fcntl ':mode';

my $cache;
my $nocache=0;
my $cachelife=60;
my $cachesize=1;
my $foreground=0;
my $help=0;

sub printusage {
  print "Usage: cgifs.pl mountpoint scriptname [-l | --cachelife] [-s | --cachesize] [-n | --nocache] [-f | --foreground] [-h | --help]\n";
  print " mountpoint: directory to mount at\n";
  print " scriptname: full path to script that will be run\n\n";
  print " -l, --cachelife: cache lifetime, in seconds (default 60 seconds)\n";
  print " -s, --cachesize: cache size, in MB (default: 1)\n";
  print " -n, --nocache: don't use cache\n";
  print " -f, --foreground: run in foreground (default behaviour is to daemonize)\n";
  print " -h, --help: print this usage message\n\n"; 
  print "Example: cgifs.pl /mnt/cgifs /usr/bin/script.php -l 120 -s 10\n";
  exit;
}

GetOptions(
  'l|cachelife:i' => \$cachelife,
  's|cachesize:i' => \$cachesize,
  'f|foreground' => \$foreground,
  'n|nocache' => \$nocache,
  'h|?|help' => \$help,
) || printusage();


if($help) {
  printusage();
  die;
}

if(!$nocache) {
  use CHI;
}

my ($script, $mountpoint);
my($u,$p, $uid,$gid) = getpwuid $>;

$cache=CHI->new(driver => 'File', root_dir=>'/tmp/cgifs-cache', expires_in => $cachelife,
  l1_cache => {driver => 'Memory', global => 1, max_size=>$cachesize*1014*1024}
) unless $nocache;

my $now=time();

my (%files) = (
  '.' => {
    type => S_IFDIR,
    mode => 0755,
    ctime => $now,
  },
  '..' => {},
);

sub filename_fixup {
  my $filename = shift;
  $filename =~ s#^/##;
  $filename = '.' unless length($filename);
  return $filename;
}

sub cgifs_getdir {
  $cache->purge() unless $nocache;
  if($nocache) {
    return (keys %files), 0;
  } else {
    return (keys %files),$cache->get_keys,0;
  }
}

sub cgifs_getattr {
  my $file = filename_fixup(shift);
  my $mode = S_IFREG + 0444;
  my ($atime, $ctime, $mtime, $size) = (0,0,0,0);
  if($file eq '.') {    
    $mode = S_IFDIR + 0555;
    $size = 0;
    $atime=$ctime=$mtime=$now; 
  } else {
    $size=length(get_contents($file));
    if($nocache) {
      $atime=$ctime=$mtime=time();
    } else {
      my $obj=$cache->get_object($file);
      if ($obj) {
        $atime=$ctime=$mtime=$obj->created_at();
      }
    }
  }
  my $blksize=4096;
  my ($dev, $ino, $rdev, $blocks,$nlink) = (0,0,0,ceil($size/$blksize),1);
  return ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,$atime,$mtime,$ctime,$blksize,$blocks);
}

sub cgifs_read {
  my $file=filename_fixup(shift);
  return get_contents($file);
}

sub cgifs_open {
  if($nocache) { return; }
  my ($path, $flags) = @_;
  $path=filename_fixup($path);
  if($cache->is_valid($path) && $flags & O_WRONLY) {
    $cache->remove($path);
  }
  return 0;
}

sub cgifs_unlink {
  if($nocache) { return; }
  my $file=shift;
  $file=filename_fixup($file);
  if($cache->is_valid($file)) {
    $cache->remove($file);
    return 0;
  } else {
    return -&ENOENT;
  }
}

sub get_contents {
  my $file=shift;
  $file=filename_fixup($file);
  if($nocache) { return `$script $file` }
  return $cache->compute($file, undef, sub{
      my $output=`$script $file`;
      return $output;
    });
}

$mountpoint = shift(@ARGV) if @ARGV;
$script = shift(@ARGV) or die;

if(!-d $mountpoint) {
  print "Error: mountpoint $mountpoint is not a directory\n";
  exit -&ENOTDIR;
}

if(!-f $script) {
  print "Error: $script not found (did you specify the full path?)\n";
  exit -&ENOENT;
}

if(!-x $script) {
  print "Error: $script is not executable\n";
  exit -&ENOENT;
}

sub daemonize {
  chdir("/") || die "can't chdir to /: $!";
  open(STDIN, "< /dev/null") || die "can't read /dev/null: $!";
  open(STDOUT, "> /dev/null") || die "can't write to /dev/null: $!";
  defined(my $pid = fork()) || die "can't fork: $!";
  exit if $pid; # non-zero now means I am the parent
  (setsid() != -1) || die "Can't start a new session: $!";
  open(STDERR, ">&STDOUT") || die "can't dup stdout: $!";
}

daemonize() unless $foreground;

Fuse::main(
  mountpoint=>$mountpoint,
  getattr=>"main::cgifs_getattr",
  getdir =>"main::cgifs_getdir",
  read=>"main::cgifs_read",
  open=>"main::cgifs_open",
  utime=>sub {return 0;},
  unlink=>"main::cgifs_unlink",
  threaded=>0,
);


END {
  $cache->clear() unless (!defined $cache || $nocache);
}
