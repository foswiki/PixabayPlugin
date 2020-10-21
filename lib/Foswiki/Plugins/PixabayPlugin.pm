# Plugin for Foswiki - The Free and Open Source Wiki, https://foswiki.org/
#
# PixabayPlugin is Copyright (C) 2019-2020 Michael Daum http://michaeldaumconsulting.com
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

our $VERSION = '2.00';
our $RELEASE = '21 Oct 2020';
our $SHORTDESCRIPTION = 'Pixabay stock images and videos';
our $NO_PREFS_IN_TOPIC = 1;
our $core;

sub initPlugin {

  Foswiki::Func::registerTagHandler('PIXABAY', sub { return getCore()->PIXABAY(@_); });

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
  undef $core;
}

1;
