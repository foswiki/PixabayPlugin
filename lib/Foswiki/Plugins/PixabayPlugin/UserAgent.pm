# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# PixabayPlugin is Copyright (C) 2019 Michael Daum http://michaeldaumconsulting.com
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details, published at
# http://www.gnu.org/copyleft/gpl.html

package Foswiki::Plugins::PixabayPlugin::UserAgent;

use strict;
use warnings;

use Foswiki::Func();
use Cache::FileCache ();
use LWP::UserAgent();
our @ISA = qw( LWP::UserAgent );

use constant TRACE => 0; # toggle me

sub new {
  my $class = shift;

  my $this = $class->SUPER::new(@_);

  my $proxy = $Foswiki::cfg{PROXY}{HOST};
  if ($proxy) {
    $this->proxy(['http', 'https'], $proxy);

    my $noProxy = $Foswiki::cfg{PROXY}{NoProxy};
    if ($noProxy) {
      my @noProxy = split(/\s*,\s*/, $noProxy);
      $this->no_proxy(@noProxy);
    }
  }

  $this->{cacheExpire} = $Foswiki::cfg{PixabayPlugin}{CacheExpire};
  $this->{cacheExpire} = "1 d" unless defined $this->{cacheExpire}; 

  return $this;
}

sub cache {
  my $this = shift;

  unless ($this->{cache}) {
    $this->{cache} = Cache::FileCache->new({
        'cache_root' => Foswiki::Func::getWorkArea('PixabayPlugin') . '/cache',
        'default_expires_in' => $this->{cacheExpire},
        'directory_umask' => 077,
      }
    );
  }

  return $this->{cache};
}

sub request {
  my $this = shift;
  my @args = @_;
  my $request = $args[0];

  return $this->SUPER::request(@args) if $request->method ne 'GET';

  my $url = $request->uri->as_string;
  my $obj = $this->getCacheEntry($url);
  if (defined $obj) {
    return HTTP::Response->parse($obj);
  }

  my $res = $this->SUPER::request(@args);
  #_writeDebug("http code=".$res->code());

  ## cache only "200 OK" content
  if ($res->code eq HTTP::Status::RC_OK || $res->code eq HTTP::Status::RC_NOT_MODIFIED) {
    _writeDebug("... setting response to cache for $url");
    $this->cache->set($url, $res->as_string, $this->{cacheExpire});
  }

  return $res;
}

sub mirror {
  my ($this, $url, $filePath) = @_;

  my $obj = $this->getCacheEntry($url);

  if ($obj) {
     if (!-e $filePath) {
      _writeDebug("file not found on disk anymore ... deleting cache entry");
      $this->cache->remove($url);
      $obj = undef;
    }
  } else {
     if (-e $filePath) {
      _writeDebug("file found on disk but not in cache... deleting file");
      unlink($filePath);
    }
  }

  return HTTP::Response->parse($obj) if defined $obj;
  return $this->SUPER::mirror($url, $filePath);
}

sub getCacheEntry {
  my ($this, $url) = @_;

  my $cgiObj = Foswiki::Func::getRequestObject();
  my $refresh = $cgiObj->param("refresh") || '';
  $refresh = ($refresh =~ /^(on|image|img|pixabay)$/) ? 1:0;

  my $obj;

  unless ($refresh) {
    _writeDebug("looking up cache for $url");
    $obj = $this->cache->get($url);
    _writeDebug("... found in cache") if $obj;
    _writeDebug("... not found in cache") unless $obj;
  }

  return $obj;
}

sub _writeDebug {
  return unless TRACE;
  #Foswiki::Func::writeDebug("PixabayPlugin::Core - $_[0]");
  print STDERR "PixabayPlugin::UserAgent - $_[0]\n";
}

1;

