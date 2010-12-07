package MT::TweetFlickrPhotostreamFix::L10N::ja;
use strict;
use base qw/ MT::TweetFlickrPhotostreamFix::L10N MT::L10N MT::Plugin::L10N /;
use vars qw( %Lexicon );

our %Lexicon = (
    'Available TweetFlickrPhotostreamFix.' => 'Flickr の photostream をつぶやきます(OAuth 対応)。<br />run-periodic-tasks の実行によって動作します。',
    'TweetFlickrPhotostreamFix Task' => 'TweetFlickrPhotostreamFix のタスク',
    'Failed to get response from [_1], ([_2])' => '[_1]から応答を得られません。([_2])',
    'Authorize error' => '認証エラー',
    'Authorize this plugin and enter the PIN#.' => 'このプラグインを認証してから、PIN番号を入力してください。',
    'Get PIN#' => 'PIN番号を取得する',
    'Done' => '実行',
    'Authentication' => '認証',
    'OAuth authentication' => 'OAuthによる認証',
    'Authentication succeeded' => '認証に成功しました',
    'Authentication failed' => '認証に失敗しました',
    'Settings for Twitter' => 'Twitter に関する設定',
    'Settings for Flickr' => 'Flickr に関する設定',
    'Flickr ID' => 'Flickr の ID',
    'Tweet format' => 'つぶやきのフォーマット',
    'Update twitter success: [_1]' => 'つぶやきました: [_1]',
);

1;
