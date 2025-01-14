# ---+ Extensions
# ---++ PixabayPlugin
# This is the configuration used by the <b>PixabayPlugin</b>.

# **STRING**
# Your API key. See https://pixabay.com/api/docs/#api_search_images
$Foswiki::cfg{PixabayPlugin}{APIKey} = '';

# **PATH**
# The directory path where requested images and videos are cached.
$Foswiki::cfg{PixabayPlugin}{CacheDir} = '$Foswiki::cfg{PubDir}/$Foswiki::cfg{SystemWebName}/PixabayPlugin/cache';

# **PATH**
# The url matching the CacheDir where requested images and videos are fetched from.
$Foswiki::cfg{PixabayPlugin}{CacheUrl} = '$Foswiki::cfg{PubUrlPath}/$Foswiki::cfg{SystemWebName}/PixabayPlugin/cache';

# **STRING**
# Caching time for downloaded assets, defaults to one month.
$Foswiki::cfg{PixabayPlugin}{CacheExpire} = '1M';

1;
