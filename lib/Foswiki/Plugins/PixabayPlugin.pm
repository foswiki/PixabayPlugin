# Plugin for Foswiki - The Free and Open Source Wiki, https://foswiki.org/
#
# PixabayPlugin is Copyright (C) 2019-2025 Michael Daum http://michaeldaumconsulting.com
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

package Foswiki::Plugins::PixabayPlugin;

use strict;
use warnings;

use Foswiki::Func ();

our $VERSION = '2.01';
our $RELEASE = '%$RELEASE%';
our $SHORTDESCRIPTION = 'Pixabay stock images and videos';
our $LICENSECODE = '%$LICENSECODE%';
our $NO_PREFS_IN_TOPIC = 1;
our $core;

sub initPlugin {

  Foswiki::Func::registerTagHandler('PIXABAY', sub { return getCore()->PIXABAY(@_); });

  Foswiki::Func::registerRESTHandler('purgeCache', sub { return getCore()->purgeCache(@_); },
    authenticate => 1,
    validate => 0,
    http_allow => 'GET,POST',
  );

  return 1;
}

sub getCore {
  unless (defined $core) {
    require Foswiki::Plugins::PixabayPlugin::Core;
    $core = Foswiki::Plugins::PixabayPlugin::Core->new();
  }
  return $core;
}

sub finishPlugin {
  $core->finish() if defined $core;
  undef $core;
}

1;
