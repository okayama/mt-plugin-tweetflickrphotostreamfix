package MT::Plugin::TweetFlickrPhotostreamFix;
use strict;
use MT;
use MT::Plugin;
use base qw( MT::Plugin );

use MT::AtomServer;

use Encode;
use Encode::Base58;
use XML::Simple;
use utf8;
use HTML::TreeBuilder;

our $PLUGIN_NAME = 'TweetFlickrPhotostreamFix';
our $PLUGIN_VERSION = '1.0';

our $CONSUMER_KEY = '9JHy3ooDpQDLH8RQGHfww';
our $CONSUMER_SECRET = 'WcthK1pcLTxs8iwobB5bIcYzEsxatsOR8xhXoMcprE';

my $plugin = new MT::Plugin::TweetFlickrPhotostreamFix( {
    id => $PLUGIN_NAME,
    key => lc $PLUGIN_NAME,
    name => $PLUGIN_NAME,
    version => $PLUGIN_VERSION,
    description => '<MT_TRANS phrase=\'Available TweetFlickrPhotostreamFix.\'>',
    author_name => 'okayama',
    author_link => 'http://weeeblog.net/',
    l10n_class => 'MT::' . $PLUGIN_NAME . '::L10N',
	blog_config_template => \&_blog_config_template,
    settings => new MT::PluginSettings( [
        [ 'access_token' ],
        [ 'access_secret' ],
        [ 'flickr_id' ],
        [ 'last_modified' ],
        [ 'last_tweeted' ],
        [ 'tweet_format', { Default => '*author* uploaded *title* to Flickr: *shoter_url* #flickr #TweetFlickrPhotostream' } ],
    ] ),
} );
MT->add_plugin( $plugin );

sub init_registry {
    my $plugin = shift;
    $plugin->registry( {
        applications => {
            cms => {
				methods => {
					tweetfpsfix_oauth => \&_mode_tweetfpsfix_oauth,
					tweetfpsfix_get_access_token => \&_mode_tweetfpsfix_get_access_token,
				},
            },
        },
        tasks => {
            tweetflickrphotostream => {
                label => 'TweetFlickrPhotostreamFix Task',
                frequency => 5,
                code => \&tweet_flickr_photostream,
            },
        },
        tags => {
            function => {
                'FlickrShorterURL' => \&_hdlr_flickr_shorter_url,
            },
        },
   } );
}

sub _blog_config_template {
	my $plugin = shift;
	my ( $param,  $scope ) = @_;
	my $tmpl = $plugin->load_tmpl( lc $PLUGIN_NAME . '_config_blog.tmpl' );
	my $blog_id = $scope;
	$blog_id =~ s/blog://;
	$tmpl->param( 'blog_id' => $blog_id );
	return $tmpl; 
}

sub tweet_flickr_photostream_by_id {
    my ( $photo_id, $blog_id ) = @_;
    return unless $photo_id;
    return unless $blog_id;
    my $shorter_url = get_shorter_url( $photo_id );
    my $ua = MT->new_ua;
    my $req = HTTP::Request->new( GET => $shorter_url ) or return;
    $req->header( 'User-Agent' => "$PLUGIN_NAME/$PLUGIN_VERSION" );
    my $res = $ua->request( $req ) or return;
    if ( $res->is_success ) {
        my $content = $res->decoded_content;
        my $tree = HTML::TreeBuilder->new;
        $tree->parse( $content );
        my ( $author, $title, $description );
        for my $meta ( $tree->find( 'meta' ) ) {
            my $name = $meta->attr( 'name' );
            next unless $name;
            if ( $name eq 'title' ) {
                $title = $meta->attr( 'content' );
                $title = MT::I18N::utf8_off( $title );
            }
            if ( $name eq 'description' ) {
                $description = $meta->attr( 'content' );
                $description = MT::I18N::utf8_off( $description );
            }
        }
        if ( my $element_username = $tree->look_down( "class", "username" ) ) {
            my $element_author = $element_username->find( 'a' );
            $author = $element_author->as_text;
            $author = MT::I18N::utf8_off( $author );
        }
        my $scope = 'blog:' . $blog_id;
        my $tweet = $plugin->get_config_value( 'tweet_format', $scope );
        $tweet = MT::I18N::utf8_off( $tweet );
        my $search_shoter_url = quotemeta( '*shoter_url*' );
        my $search_title = quotemeta( '*title*' );
        my $search_content = quotemeta( '*content*' );
        my $search_author = quotemeta( '*author*' );
        $tweet =~ s/$search_shoter_url/$shorter_url/g;
        $tweet =~ s/$search_title/$title/g;
        $tweet =~ s/$search_content/$content/g;
        $tweet =~ s/$search_author/$author/g;
        print $tweet . "\n";
        if ( my $res = $plugin->update_twitter( $tweet, $blog_id ) ) {
            my $log_message = $plugin->translate( 'Update twitter success: [_1]', $res );
            _save_success_log( $log_message, $blog_id );
        }
    }
}

sub _hdlr_flickr_shorter_url {
    my ( $ctx, $args, $cond ) = @_;
    if ( my $photo_id = $args->{ photo_id } ) {
        if ( $photo_id =~ /^[0-9]{1,}$/ ) {
            return get_shorter_url( $photo_id ) || '';
        }
    }
    return '';
}

sub tweet_flickr_photostream {
    my @blogs = MT->model( 'blog' )->load( { class => '*' } );
    for my $blog ( @blogs ) {
        my $blog_id = $blog->id;
        my $scope = 'blog:' . $blog_id;
        if ( my $flickr_id = $plugin->get_config_value( 'flickr_id', $scope ) ) {
            if ( my $rss_url = _get_rss_url( $flickr_id ) ) {
                my $tweet_format = $plugin->get_config_value( 'tweet_format', $scope );
                my $last_modified = $plugin->get_config_value( 'last_modified', $scope );
                my $last_tweeted = $plugin->get_config_value( 'last_tweeted', $scope );
                if ( my $tweets = _get_tweet( $blog_id, $rss_url, $tweet_format, $last_modified, $last_tweeted ) ) {
                    my $updated = 0;
                    for my $tweet ( @$tweets ) {
                       if ( my $res = $plugin->update_twitter( $tweet, $blog_id ) ) {
                            my $log_message = $plugin->translate( 'Update twitter success: [_1]', $res );
                            _save_success_log( $log_message, $blog_id );
                            $last_tweeted = time;
                            $updated++;
                       }
                    }
                    if ( $updated ) {
                        $plugin->set_config_value( 'last_tweeted', $last_tweeted, $scope );
                    }
                }
            }
        }
    }
}

sub _get_tweet {
    my ( $blog_id, $rss_url, $format, $last_modified, $last_tweeted ) = @_;
    return unless $blog_id;
    return unless $rss_url;
    return unless $format;
    my $ua = MT->new_ua;
    my $req = HTTP::Request->new( GET => $rss_url ) or return;
    $req->header( 'User-Agent' => "$PLUGIN_NAME/$PLUGIN_VERSION" );
    if ( $last_modified ) {
        $req->header( 'If-Modified-Since' => $last_modified );
    }
    my $res = $ua->request( $req ) or return;
    if ( $res->is_success ) {
        my $content = $res->content;
        my $ref = XMLin( $content, NormaliseSpace => 2 );
        if ( defined $ref->{ xmlns } && $ref->{ xmlns } eq 'http://www.w3.org/2005/Atom' ) {
            my %items = %{ $ref->{ entry } } or return;
            my @tweets;
            for my $key ( keys %items ) {
                my $updated = $items{ $key }->{ updated };
                my $updated_epoch = MT::AtomServer::iso2epoch( undef, $updated );
                if ( $last_tweeted && ( $updated_epoch < $last_tweeted ) ) {
                    next;
                }
                if ( my $photo_id = $key ) {
                    $photo_id =~ s!.*/([0-9]{1,})!$1!;
                    if ( my $shorter_url = get_shorter_url( $photo_id ) ) {
                        my $tweet = $format;
                        my $title = $items{ $key }->{ title };
                        my $content = $items{ $key }->{ content }->{ content };
                        my $author = $items{ $key }->{ author }->{ name };
                        $title = MT::I18N::utf8_off( $title );
                        $content = MT::I18N::utf8_off( $content );
                        $author = MT::I18N::utf8_off( $author );
                        $title = decode_utf8( $title );
                        $content = decode_utf8( $content );
                        $author = decode_utf8( $author );
                        my $search_shoter_url = quotemeta( '*shoter_url*' );
                        my $search_title = quotemeta( '*title*' );
                        my $search_content = quotemeta( '*content*' );
                        my $search_author = quotemeta( '*author*' );
                        $tweet =~ s/$search_shoter_url/$shorter_url/g;
                        $tweet =~ s/$search_title/$title/g;
                        $tweet =~ s/$search_content/$content/g;
                        $tweet =~ s/$search_author/$author/g;
                        $tweet = MT::I18N::utf8_off( $tweet );
                        push( @tweets, $tweet );
                        unless ( $last_modified ) {
                            last;
                        }
                    }
                }
            }
            my $scope = 'blog:' . $blog_id;
            $plugin->set_config_value( 'last_modified', $res->header( 'Last-Modified' ), $scope );
            return \@tweets;
        }
    } else {
#        my $log_message = $plugin->translate( 'Getting RSS failed.' );
#        _save_error_log( $log_message, $blog_id );
    }
    return 0;
}

sub get_shorter_url {
    my ( $photo_id ) = @_;
    return unless $photo_id;
    if ( $photo_id =~ /^[0-9]{1,}$/ ) {
        if ( my $encoded = encode_base58( $photo_id ) ) {
            return 'http://flic.kr/p/'. $encoded;
        }
    }
    return '';
}

sub _get_rss_url {
    my ( $flickr_id ) = @_;
    if ( $flickr_id ) {
        return 'http://api.flickr.com/services/feeds/photos_public.gne?id=' . $flickr_id . '&lang=en-us&format=atom';
    }
}

sub get_setting {
	my ( $plugin, $key, $blog_id ) = @_;
	my $scope = $blog_id  ? 'blog:' . $blog_id : 'system';
	return $plugin->get_config_value( $key, $scope );
}

sub access_token {
	my $plugin = shift;
	return $plugin->get_setting( 'access_token', @_ );
}

sub access_token_secret {
	my $plugin = shift;
	return $plugin->get_setting( 'access_token_secret', @_ );
}

sub consumer_key {
	my $plugin = shift;
	return $CONSUMER_KEY;
}

sub consumer_secret {
	my $plugin = shift;
	return $CONSUMER_SECRET;
}

sub update_twitter {
	my ( $plugin, $msg, $blog_id ) = @_;
	$msg = decode_utf8( $msg );
	require Net::OAuth::Simple;
	my %tokens  = (
		'access_token' => $plugin->access_token( $blog_id ),
		'access_token_secret' => $plugin->access_token_secret( $blog_id ),
		'consumer_key' => $plugin->consumer_key( $blog_id ) ,
		'consumer_secret' => $plugin->consumer_secret( $blog_id ),
	);
	my $nos = Net::OAuth::Simple->new(
		tokens => \%tokens,
		protocol_version => '1.0a',
		urls => {
			authorization_url => 'https://twitter.com/oauth/authorize',
			request_token_url => 'https://twitter.com/oauth/request_token',
			access_token_url => 'https://twitter.com/oauth/access_token',
		}
	);
	return $plugin->trans_error( "Authorize error" ) unless $nos->authorized;
	my $url  = "http://api.twitter.com/1/statuses/update.xml";
	my %params = ( 'status' => $msg );
	my $response;
	eval { $response = $nos->make_restricted_request( $url, 'POST', %params ); };
	if ( $@ ) {
		my $err = $@;
		return $plugin->trans_error( "Failed to get response from [_1], ([_2])", "twitter", $err );
	}
	unless ( $response->is_success ) {
	    return $plugin->trans_error( "Failed to get response from [_1], ([_2])", "twitter", $response->status_line );
	}
	return $msg;
1;
}

sub _mode_tweetfpsfix_oauth {
	my $app = shift;
	my $q = $app->{ query };
	my $blog_id = $q->param( 'blog_id' );
	
	my $tmpl = $plugin->load_tmpl( 'oauth_start.tmpl' );
	
	require Net::OAuth::Simple;
	my %tokens = (
		'consumer_key' => $plugin->consumer_key( $blog_id ),
		'consumer_secret' => $plugin->consumer_secret( $blog_id ),
	);
	my $nos = Net::OAuth::Simple->new(
		tokens => \%tokens,
		protocol_version => '1.0',
		urls => {
			authorization_url => 'https://twitter.com/oauth/authorize',
			request_token_url => 'https://twitter.com/oauth/request_token',
			access_token_url  => 'https://twitter.com/oauth/access_token',
		}
	);

	my $url;
	eval { $url = $nos->get_authorization_url(); };
	if ( $@ ) {
		my $err = $@;
		$tmpl->param( 'error_authorization' => 1 );
	} else {
		my $request_token = $nos->request_token;
		my $request_token_secret = $nos->request_token_secret;
		$tmpl->param( 'access_url' => $url );
		$tmpl->param( 'request_token' => $request_token );
		$tmpl->param( 'request_token_secret' => $request_token_secret );
	}
	return $tmpl; 
}

sub _mode_tweetfpsfix_get_access_token {
	my $app = shift;
	my $q = $app->{ query };
	my $blog_id = $q->param( 'blog_id' );

	my $new_pin = $q->param( 'tweetflickrphotostreamfix_pin' ) || q{};
	my $tmpl = $plugin->load_tmpl( 'oauth_finished.tmpl' );

	my %tokens  = (
		'consumer_key' => $plugin->consumer_key( $blog_id ),
		'consumer_secret' => $plugin->consumer_secret( $blog_id ),
		'request_token' => $q->param( 'request_token' ),
		'request_token_secret' => $q->param( 'request_token_secret' ),
	);
	require Net::OAuth::Simple;
	my $nos = Net::OAuth::Simple->new(
		tokens => \%tokens,
		protocol_version => '1.0a',
		urls => {
			authorization_url => 'https://twitter.com/oauth/authorize',
			request_token_url => 'https://twitter.com/oauth/request_token',
			access_token_url  => 'https://twitter.com/oauth/access_token',
		}
	);
	$nos->verifier( $new_pin );
	my ( $access_token, $access_token_secret, $user_id, $screen_name );
	eval { ( $access_token, $access_token_secret, $user_id, $screen_name ) =  $nos->request_access_token(); };
	if ( $@ ) {
		my $err = $@;
		$tmpl->param( 'error_verification' => 1 );
	} else {
		$tmpl->param( 'verified_screen_name' => $screen_name );
		$tmpl->param( 'verified_user_id' => $user_id );
		my $scope = 'blog:' . $blog_id;
		$plugin->set_config_value( 'access_token', $access_token, $scope );
		$plugin->set_config_value( 'access_token_secret', $access_token_secret, $scope );
	}
	$tmpl;
}

sub _save_success_log {
    my ( $message, $blog_id ) = @_;
    _save_log( $message, $blog_id, MT::Log::INFO() );
}

sub _save_error_log {
    my ( $message, $blog_id ) = @_;
    _save_log( $message, $blog_id, MT::Log::ERROR() );
}

sub _save_log {
    my ( $message, $blog_id, $log_level ) = @_;
    if ( $message ) {
        my $log = MT::Log->new;
        $log->message( $message );
        $log->class( 'tweetflickrphotostream' );
        $log->blog_id( $blog_id );
        $log->level( $log_level );
        $log->save or die $log->errstr;
    }
}

sub _debug {
    my ( $data ) = @_;
    use Data::Dumper;
    MT->log( Dumper( $data ) );
}

1;
