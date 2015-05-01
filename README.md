# cgifs

As a sysadmin, I've written many web-based scripts so that I can do something like

> wget http://www.example.com/getconfig.php?hostname=computer.example.com

to dynamically generate a config file given an argument (which might be the hostname of the computer being configured, or any other argument). getconfig.php will then dynamically generate the desired config file, perhaps by in turn making database queries or the like.

However, what if you can't make a request to a web server, and are instead restricted to simply reading a file from a filesystem but still want dynamically-generated file contents? Or, perhaps you'd like to dynamically generate your web content but libapache2-mod-exotic-language doesn't exist? Then, cgifs might solve your problem! cgifs also caches the output of your script - see below. (caching is enabled by default, but can be disabled if you prefer)

Basic usage
-----------
To mount a filesystem at /mnt/cgifs:

    ./cgifs.pl /mnt/cgifs /usr/bin/script.php

The mountpoint (first argument) must already exist, and the script (second argument) must be executable, with a fully-specified path. If you then:

    cat /mnt/cgifs/helloworld

the output will be the same as running "/usr/bin/script.php helloworld": the script is called with a single argument (the name of the file you tried to read), and the contents of the file will be given by whatever script.php prints to stdout (specifically, you'll get: my $out=\`$script $filename\`; print $out). 

Because cgifs uses Fuse, you can unmount by running

    fusemount -u /mnt/cgifs

when you're done.

Dependencies
------------
You need the [Perl Fuse module](http://search.cpan.org/dist/Fuse/Fuse.pm). Also, unless you specify the --nocache option (see below), you will also need the [Perl CHI module](http://search.cpan.org/~jswartz/CHI-0.59/lib/CHI.pm). On a Debian-like system, you can simply

    apt-get install libfuse-perl libchi-perl

or you can install the modules from CPAN.

Full Usage instructions
-----------------------
    cgifs.pl mountpoint scriptname [-l | --cachelife] [-s | --cachesize] [-n | --nocache] [-f | --foreground] [-h | --help]

    mountpoint: directory to mount at
    scriptname: full path to script that will be run

    -l, --cachelife: cache lifetime, in seconds (default 60 seconds)
    -s, --cachesize: cache size, in MB (default: 1)
    -n, --nocache: don't use cache
    -f, --foreground: run in foreground (default behaviour is to daemonize)
    -h, --help: print this usage message

So for example, to call /home/alt36/script.sh by mounting under /tmp/script/ with a cache life of 2 minutes (120 seconds) and cache size of 10 MB:
    
    cgifs.pl /tmp/script /home/alt36/script.sh -l 120 -s 10

Caching
-------
[CHI](http://search.cpan.org/~jswartz/CHI-0.59/lib/CHI.pm) is used to cache, unless --nocache is specified. Cached data is stored both on disk (under /tmp/cgifs-cache) and in RAM. The size of the disk-backed cache is unlimited (well, up to the size of your disk!), whilst the RAM-backed cache has a size specified by --cachesize (default: 1MB). Data will stay in the cache for the time specified by --cachelife (default: 60 seconds). 

To see all currently cached objects:

    ls /mnt/cgifs

The mtime (and ctime and atime, for that matter) of the files will correspond to the time the cache entry was last updated. The filesize should match the size of the cached data.

To force a cache refresh for a file:

    touch /mnt/cgifs/filename

To remove a file from the cache (which will therefore effectively also lead to a cache refresh the next time you read the file):

    rm /mnt/cgifs/filename

If you specify the --nocache option, no caching will be used, and ls will only return entries for . and ..

The cache is cleared when the filesystem is unmounted.

Background/motivation
---------------------
We use [hobbit/xymon](http://xymon.sourceforge.net/) to monitor computers in our organisation, and therefore also install [bbwin](http://bbwin.sourceforge.net/) on our Windows clients so they can report client data. One can tell bbwin to download its configuration file from the central hobbit server by including a stanza in bbwin.cfg such as 

    <configuration>
    <bbwinupdate>
        <setting name="filename" value="bbwin/%COMPUTERNAME%.cfg" />
    </bbwinupdate>
    </configuration>

bbwin will then transfer bbwin/%COMPUTERNAME%.cfg from the central hobbit server, using its own internal protocols. Therefore, wouldn't it be useful if the contents of bbwin/%COMPUTERNAME%.cfg could be dynamically generated on the server, with the contents dependent on the value of %COMPUTERNAME% ?
