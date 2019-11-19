# Plugin for Foswiki - The Free and Open Source Wiki, https://foswiki.org/
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

package Foswiki::Plugins::PixabayPlugin::Core;

use strict;
use warnings;

use Foswiki::Func ();
use Foswiki::Plugins::PixabayPlugin::WebService ();
use Foswiki::Plugins::PixabayPlugin::UserAgent ();

use constant TRACE => 0; # toggle me
#use Data::Dump qw(dump); # disable for production
#use Log::Tiny ();

sub new {
  my $class = shift;

  my $this = bless({
    cacheDir => $Foswiki::cfg{PixabayPlugin}{CacheDir} || $Foswiki::cfg{PubDir} . '/' . $Foswiki::cfg{SystemWebName} . '/PixabayPlugin/cache',
    cacheUrl => $Foswiki::cfg{PixabayPlugin}{CacheUrl} || $Foswiki::cfg{PubUrlPath} . '/' . $Foswiki::cfg{SystemWebName} . '/PixabayPlugin/cache',
    apiKey => $Foswiki::cfg{PixabayPlugin}{APIKey},
    @_
  }, $class);

  mkdir $this->{cacheDir} unless -d $this->{cacheDir};

  return $this;
}

sub DESTROY {
  my $this = shift;

  undef $this->{_webService};
  undef $this->{_userAgent};
}

sub PIXABAY {
  my ($this, $session, $params, $topic, $web) = @_;

  #_writeDebug("called PIXABAY(".$params->stringify().")") if TRACE;

  my $type = $params->{type} || 'photo';
  $type = 'film' if $type eq 'video';
  my $isImage = $type =~ /^(photo|illustration|vector|allimages)$/?1:0;
  my $isVideo = $type =~ /^(film|animation|allvideos)$/?1:0;
  $type = 'all' if $type =~ /^(all(images|videos))$/;
  $params->{type} = $type;

  return _inlineError("unknown category")
    unless !$params->{category}
    || $params->{category} =~ /^(fashion|nature|backgrounds|science|education|people|feelings|religion|health|places|animals|industry|food|computer|sports|transportation|travel|buildings|business|music)$/;

  $params->{safesearch} = Foswiki::Func::isTrue($params->{safesearch}, 0)?'true':'false';
  $params->{min_width} ||=  0;
  $params->{min_height} ||= 0;
  $params->{editors_choice} = Foswiki::Func::isTrue($params->{editors_choice}, 0)?'true':'false';
  $params->{order} ||= 'popular';
  $params->{lang} ||= $session->i18n->language();

  return _inlineError("unknown order") unless $params->{order} =~ /^(popular|latest)$/;
  return _inlineError("illegan 'random' parameter") if $params->{random} && $params->{random} !~ /^\d+$/;

  return $this->handleImage($params, $web, $topic) if $isImage;
  return $this->handleVideo($params, $web, $topic) if $isVideo;

  return _inlineError("unknown image or video type");
}

sub handleImage {
  my ($this, $params, $web, $topic) = @_;

  my %opts = ();

  $opts{q} = $params->{_DEFAULT} || '';
  $opts{id} = $params->{id} if defined $params->{id};
  if (!defined($opts{id}) && $opts{q} =~ /^\d+$/) {
    $opts{id} = $opts{q};
    delete $opts{q};
  }

  $opts{image_type} = $params->{type};
  $opts{category} = $params->{category} if $params->{category};
  $opts{safesearch} = $params->{safesearch};
  $opts{min_width} = $params->{min_width};
  $opts{min_height} = $params->{min_height};
  $opts{editors_choice} = $params->{editors_choice};
  $opts{order} = $params->{order};
  $opts{lang} = $params->{lang};

  if (defined $params->{colors} || defined $params->{color}) {
    $opts{colors} = $params->{colors} || $params->{color};
    foreach my $color (split(/\s*,\s*/, $opts{colors})) {
      return _inlineError("unknown color") unless $color =~ /^(grayscale|transparent|red|orange|yellow|green|turquoise|blue|lilac|pink|white|gray|black|brown)$/;
    }
  }

  if (defined $params->{orientation}) {
    $opts{orientation} = $params->{orientation};
    return _inlineError("unkown orientation") unless $opts{orientation} =~ /^(horizontal|vertical|all)$/;
  }

  my $format = $params->{format} // '<img src=\'$url\' width=\'$width\' height=\'$height\' alt=\'$id\' $class />';
  my $width = $params->{width};
  my $height = $params->{height};

  my $size = $params->{size} || 'web';
  my $urlKey = '';	
  if ($size eq 'orig') {
    $urlKey = '$imageURL';
    $width ||= '$imageWidth';
    $height ||= '$imageHeight';
  } elsif ($size eq 'fullhd') {
    $urlKey = '$fullHDURL';
    $width ||= '$fullHDWidth';
    $height ||= '$fullHDHeight';
  } elsif ($size eq 'large') {
    $urlKey = '$largeImageURL';
    $width ||= '';
    $height ||= '';
  } elsif ($size eq 'web') {
    $urlKey = '$webformatURL';
    $width ||= '$webformatWidth';
    $height ||= '$webformatHeight';
  } elsif ($size eq 'preview') {
    $urlKey = '$previewURL';
    $width ||= '$previewWidth';
    $height ||= '$previewHeight';
  } else {
    return _inlineError("unknown image size");
  }

  $format =~ s/\$url\b/$urlKey/g;

  my $class = $params->{class} || '';
  $class = "class='$class'" if $class;

  my $limit = $params->{limit} || 1;
  my $skip = $params->{skip} || 0;
  my $random = $params->{random} || 0;
  $skip = int(rand()*$random) if $random;
  $limit += $skip;
  my @results = ();
  my $index = 0;

  $opts{per_page} = 20;
  $opts{page} = 1;

  _writeDebug("getting page $opts{page}");

  my $response = $this->imageSearch(%opts);

  while ($response && $response->{hits}) {

    my $total = $response->{totalHits};
    _writeDebug("totalHits=$total");
    if ($total < $skip) {
      $skip = $total - 1;
      _writeDebug("downgrading skip to $skip");
    }
    if ($total < $limit) {
      $limit = $total;
      _writeDebug("downgrading limit to $limit");
    }
    if ($limit <= $skip) {
      $skip = $limit -1;
    }

    _writeDebug("random=$random,limit=$limit, skip=$skip, page=$opts{page}");

    foreach my $hit (@{$response->{hits}}) {
      $index++;

      #_writeDebug("index=$index");
      next if $index <= $skip;
      last if $limit && $index > $limit;

      my $result = $format;
      $result =~ s/\$(imageURL|fullHDURL|largeImageURL|webformatURL|previewURL|vectorURL)\b/$this->mirrorImage($hit, $1)/ge;

      my $propsRegex = join("|", keys %{$hit});

      $result =~ s/\$index\b/$index/g;
      $result =~ s/\$width\b/$width/g;
      $result =~ s/\$height\b/$height/g;
      $result =~ s/\$class\b/$class/g;
      $result =~ s/\$($propsRegex)/$hit->{$1}/g;

      push @results, $result unless $result eq "";
    }
    last if $limit && $index > $limit;

    $opts{page}++;
    last if $opts{page} * $opts{per_page} > $total;

    _writeDebug("getting page $opts{page}");
    $response = $this->imageSearch(%opts);
  }
  unless (@results) {
    _writeDebug("WARNING: no results");
    return "";
  }

  my $header = $params->{header} || '';
  my $footer = $params->{footer} || '';
  my $separator = $params->{separator} || '';
  my $count = scalar(@results);
  my $result = $header.join($separator, @results).$footer;
  $result =~ s/\$count\b/$count/g;

  return Foswiki::Func::decodeFormatTokens($result);
}

sub handleVideo {
  my ($this, $params, $web, $topic) = @_;

  my %opts = ();

  $opts{q} = $params->{_DEFAULT} || '';
  $opts{id} = $params->{id} if defined $params->{id};
  if (!defined($opts{id}) && $opts{q} =~ /^\d+$/) {
    $opts{id} = $opts{q};
    delete $opts{q};
  }

  $opts{video_type} = $params->{type};
  $opts{category} = $params->{category} if defined $params->{category};
  $opts{safesearch} = $params->{safesearch};
  $opts{min_width} = $params->{min_width};
  $opts{min_height} = $params->{min_height};
  $opts{editors_choice} = $params->{editors_choice};
  $opts{order} = $params->{order};
  $opts{lang} = $params->{lang};

  my $size = $params->{size} || 'tiny';
  return _inlineError("unknown video size") unless $size =~ /^(large|medium|small|tiny)$/;
  _writeDebug("size=$size");

  my $format = $params->{format};
  $format //= '<video width=\'$width\' height=\'$height\' $controls $autoplay $muted $loop $class alt=\'$id\'><source src=\'$url\' />Your browser does not support the video tag.</video>';

  my $width = $params->{width};
  my $height = $params->{height};

  my $controls = Foswiki::Func::isTrue($params->{controls}, 0)?"controls":"";
  my $autoplay = Foswiki::Func::isTrue($params->{autoplay}, 1)?"autoplay":"";
  my $muted = Foswiki::Func::isTrue($params->{muted}, 1)?"muted":"";
  my $loop = Foswiki::Func::isTrue($params->{loop}, 1)?"loop":"";
  my $class = $params->{class} || '';
  $class = "class='$class'" if $class;

  my $limit = $params->{limit} || 1;
  my $random = $params->{random} || 0;
  my $skip = $params->{skip} || 0;
  $skip = int(rand()*$random) if $random;
  $limit += $skip;
  my @results = ();
  my $index = 0;

  $opts{per_page} = 20;
  $opts{page} = 1;

  _writeDebug("getting page $opts{page}");
  _writeDebug("limit=$limit, skip=$skip, page=$opts{page}");

  my $response = $this->videoSearch(%opts);

  #_writeDebug(dump($response));

  while ($response && $response->{hits}) {

    my $total = $response->{totalHits};
    _writeDebug("totalHits=$total");
    if ($total < $skip) {
      $skip = $total - 1;
      _writeDebug("downgrading skip to $skip");
    }
    if ($total < $limit) {
      $limit = $total;
      _writeDebug("downgrading limit to $limit");
    }
    if ($limit <= $skip) {
      $skip = $limit -1;
    }

    foreach my $hit (@{$response->{hits}}) {
      $index++;
      next if $index <= $skip;
      last if $limit && $index > $limit;

      my $result = $format;
      my $url = $this->mirrorVideo($hit, $size);
      my $bytes = $hit->{videos}{$size}{size};
      $width ||= $hit->{videos}{$size}{width};
      $height ||= $hit->{videos}{$size}{height};

      my $propsRegex = join("|", keys %{$hit});

      $result =~ s/\$url\b/$url/g;
      $result =~ s/\$index\b/$index/g;
      $result =~ s/\$width\b/$width/g;
      $result =~ s/\$height\b/$height/g;
      $result =~ s/\$size\b/$bytes/g;
      $result =~ s/\$class\b/$class/g;
      $result =~ s/\$controls\b/$controls/g;
      $result =~ s/\$autoplay\b/$autoplay/g;
      $result =~ s/\$loop\b/$loop/g;
      $result =~ s/\$muted\b/$muted/g;
      $result =~ s/\$($propsRegex)/$hit->{$1}/g;

      push @results, $result unless $result eq "";
    }
    last if $limit && $index > $limit;

    $opts{page}++;
    last if $opts{page} * $opts{per_page} > $total;

    _writeDebug("getting page $opts{page}");
    $response = $this->videoSearch(%opts);
  }
  return "" unless @results;

  my $header = $params->{header} || '';
  my $footer = $params->{footer} || '';
  my $separator = $params->{separator} || '';
  my $count = scalar(@results);
  my $result = $header.join($separator, @results).$footer;
  $result =~ s/\$count\b/$count/g;

  return Foswiki::Func::decodeFormatTokens($result);
}

sub getFileNameOfUrl {
  my ($this, $url) = @_;

  return "" unless $url;

  my $fileName = $url;
  $fileName =~ s/^.*\/([^\/]+)$/$1/;
  $fileName =~ s/\?.*$//;

  return $fileName;
}

sub getFilePathOfUrl {
  my ($this, $url) = @_;

  return "" unless $url;
  return $this->{cacheDir}.'/'.$this->getFileNameOfUrl($url);
}

sub translateUrl {
  my ($this, $url) = @_;

  return "" unless $url;
  return $this->{cacheUrl}.'/'.$this->getFileNameOfUrl($url);
}

sub mirrorImage {
  my ($this, $hit, $key) = @_;

  my $url = $hit->{$key};
  return '' unless defined $url;
  _writeDebug("$key=$url");

  my $isOk = $this->mirror($url);

  return "" unless $isOk;
  return $this->translateUrl($url);
}

sub mirrorVideo {
  my ($this, $hit, $key) = @_;

  _writeDebug("mirrorVideo");

  my $url = $hit->{videos}{$key}{url};
  next unless defined $url;
  _writeDebug("$key=$url");

  my $isOk = $this->mirror($url);

  return "" unless $isOk;
  return $this->translateUrl($url);
}

sub mirror {
  my ($this, $url) = @_;

  _writeDebug("called mirror($url)");
  my $filePath = $this->getFilePathOfUrl($url);
  _writeDebug("filePath=$filePath");

  unless (-e $filePath){

    my $res = $this->userAgent->mirror($url, $filePath);
    return unless $res;

    unless ($res->is_success || $res->code() == 304) {
      if (TRACE) {
	_writeDebug("failed to fetch $url, code=".$res->code());
	_writeDebug("http status=".$res->status_line);
	_writeDebug("content=".$res->decoded_content);
      }
      return;
    }
  }

  return $filePath;
}

sub webService {
  my $this = shift;

  unless ($this->{_webService}) {
    _writeDebug("creating webservice");
    $this->{_webService} = Foswiki::Plugins::PixabayPlugin::WebService->new(
      #logger => Log::Tiny->new('/tmp/pixabay.log'), 
      api_key => $this->{apiKey},
      @_
    );
  }

  return $this->{_webService};
}

sub imageSearch {
  my $this = shift;

  my $response;
  eval {
    $response = $this->webService->image_search(@_);
  };
  #warn $@ if $@;

  return $response;
}

sub videoSearch {
  my $this = shift;

  my $response;
  eval {
    $response = $this->webService->video_search(@_);
  };
  #warn $@ if $@;

  return $response;
}


sub userAgent {
  my $this = shift;

  #_writeDebug("called userAgent");
  unless ($this->{_userAgent}) {
    _writeDebug("creating userAgent");
    $this->{_userAgent} = Foswiki::Plugins::PixabayPlugin::UserAgent->new(@_);
    $this->{_userAgent}->agent('Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Ubuntu Chromium/74.0.3729.169 Chrome/74.0.3729.169 Safari/537.36'); # TODO: make it configurable
  }

  return $this->{_userAgent};
}

sub purgeCache {
  my $this = shift;

  $this->userAgent->cache->purge;

  return;
}

sub clearCache {
  my $this = shift;

  $this->userAgent->cache->clear;

  return;
}

sub _writeDebug {
  return unless TRACE;
  #Foswiki::Func::writeDebug("PixabayPlugin::Core - $_[0]");
  print STDERR "PixabayPlugin::Core - $_[0]\n";
}

sub _inlineError {
  my $msg = shift;

  $msg =~ s/ at .*$//g;
  return "<span class='foswikiAlert'>".$msg.'</span>';
}

1;
