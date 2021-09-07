# os-command-injection

## 概要
webアプリケーション開発で使われれる言語は、シェル経由でOSコマンドの実行が可能なものがある。

シェル経由でOSコマンドの実行したり、
内部的にシェルを用いて実装している場合に、意図しないOSコマンドが実行可能になる恐れあり。

### 攻撃シナリオ
1. 攻撃用ツールを外部からダウンロードする

2. ダウンロードしたツールに実行権限を与える

3. OSの脆弱性を内部から攻撃して管理者権限を得る（local exploit）

4. webサーバは攻撃者の思い通りになる


### webサーバの悪用例
* webサーバ内のファイルの閲覧・改ざん・削除
* 外部へのメールの配信
* 別のサーバへの攻撃
* 暗号通貨の採掘（マイニング）

## 攻撃手法と影響

### 通常

```php
<?php
$mail = filter_input(INPUT_POST, 'mail');
system("/usr/sbin/sendmail - i < templmate.txt $mail");
```

* system
外部プログラムを実行

* sendmail
sendmail [-i] [-f 送信者アドレス] [-t] [宛先アドレス ...]
標準入力にメッセージを渡すと、そのメッセージを宛先アドレスに投げてくれる

### 攻撃
POSTされた値がただのアドレスではなく、

```bash
bob@example.jp;cat /etc/passwd
```
の場合、/etc/passwdの内容が表示される

find -execなどであれば、
検索したファイル名に対してコマンドを実行することができる。

こわい。

## 脆弱性が生まれる原因
シェルにある複数のコマンドを起動するための構文を利用して、
元のコマンドに加えて別のコマンドを起動させられる。
これがOSコマンドインジェクション。

もう１つが、内部的にシェル起動のできる関数を使っている場合。
（perlのopen関数など）

### シェルによる複数のコマンド実行
もとのコマンドに加えて別のコマンドを起動するために、、、
これを覚える（？）

```bash
echo aaa; echo bbb # コマンドを続けて実行
echo aaa & echo bbb # バックグラウンドとフォアグランドで実行
echo aaa && echo bbb # 最初のコマンドが成功したら第2のコマンドを実行
cat aaa || echo bbb # 最初のコマンドが失敗したら第2のコマンドを実行
wc `ls` # バッククォートで囲った文字列をコマンドして実行
echo aaa | wc # 第一のコマンドの出力を第2のコマンドの入力に
```
これらのメタ文字をエスケープする。

(参考)
https://qiita.com/kawaz/items/f8d68f11d31aa3ea3d1c

めんどくさそう


### シェル機能を呼び出せる関数を使用している場合
Perlのopen関数はファイルをオープンするための機能
呼び出し方に酔ってはシェル経由でOSコマンドを実行できる

検証する。

dockerで環境を作る
```sh
docker run -v $PWD/scripts:/tmp -ti perl:5.26 bash
```

```perl
#!/usr/bin/perl
open FL, '/bin/pwd|' or die $!;
print <FL>;
close FL;
```
current directory名が表示される。

```perl
#!/usr/bin/perl
use strict;
use utf8;
use open ':utf8';

my $file='ls /sbin|'; # パラメータでわたされる値. url上からは ls+/sbin|
open (IN, $file) or die $!;
print <IN>;
close IN;
```
/sbinの内容が表示される。

### 脆弱性が生まれる原因のまとめ
* シェルを呼び出す機能のある関数(system, open）などを利用している
* シェル呼び出しの機能のある関数にパラメータを渡している
* パラメータ内に含まれるシェルのメタ文字をエスケープしていない

## 対策
* OSコマンド呼び出しを使わない実装方法を検討
* シェル呼び出し機能のある関数の利用を避ける
* 外部から入力された文字列をコマンドラインのパラメータに渡さない
* OSコマンドに渡すパラメータを安全な関数によりエスケープする

### OSコマンド呼び出しを使わない実装方法

* 例
phpの場合はライブラリがあるので、mb_send_mailを使用する

（メール送信機能についてはメールヘッダ・インジェクション脆弱性がある。4.9を参照）
（徳丸本お家芸）（出張版なのやつ文法）


### シェル呼び出し機能のある関数の利用を避ける
どうしてもOSコマンドを呼び出さないといけない場合、
OSコマンドを呼び出す際にシェルを経由しない関数を使用する。
（phpにはない！）

* シェルを経由する
```perl
my $rtn = system("/bin/grep $keyword /var/data/*.txt");
```

* シェルを経由しない
```perl
my $rtn = system('/bin/grep', '--', $keyword, glob('/var/data/*.txt'));
```
コマンド名とパラメータを個別に指定する呼び出しの場合、シェルは経由されない。

メタ文字はコマンドのパラメータとして渡されるので、OSコマンド・インジェクション脆弱性は、

原理的に混入の危険性はない。

（パラメータの中で;を渡したりしても、２つ目のコマンドを実行できないから？）

  * '--'は、オプション指定がおわりこれ以降はパラメータが続くよという意味
  　これがないとkeywordに「-R」を加えて任意のオプション指定ができる

Perlのopen関数の場合は
* open関数の代わりにsysopen関数を使う
* open文の第2引数として、アクセスモードを指定する
```perl
open(FL, '<', $file) or die 'ファイルがオープンできません';
```
アクセスモードを指定するとシェル呼び出しがされない。

本には例として、
```perl
open (my $pipe, '|-', '/usr/sbin/sendmail', $mail) or die $!;
open (my $pipe, '|-', '/usr/sbin/sendmail $mail') or die $!; #これはシェル呼び出し
# ん？アクセスモード関係なくね？
```

### 外部から入力された文字列をコマンドラインのパラメータに渡さない

具体的には
```bash
sendmail -t
```
のtオプションを使用する。
こうすることにより、メールアドレスをヘッダから読み込むようになり、
OSコマンドインジェクションの余地がなくなる。

```php
<?php
// 略
$h = popen('/usr/sbin/sendmail -t -i', 'w');
fwrite($h, <<< EndOfMail
To: $mail
From: sample@hoge.com
...

EndOfMail
);
pclose($h);
```
popen関数とfwrite関数を使ってメールの文章をsendmailコマンドに送り込んでいる。


### OSコマンドに渡すパラメータを完全な関数によりエスケープする
phpの場合はescapeshellargという関数。
```php
system('/usr/sbin/sendmail <tmplate.txt ' . escapeshellarg($mail));
```
どうようの関数としてescapeshellcmdがあるが、
使い方によっては脆弱性の原因になる。

なお、
escapeshellcmdでも脆弱性が混入する可能性はある。
以下の対策で考える。


escapechellcmd攻撃実例[https://blog.tokumaru.org/2011/01/escapeshellcmd-dangerous-usage.html#p01]
escapechellcmd解説[https://blog.tokumaru.org/2011/01/php-escapeshellcmd-is-dangerous.html]


### 参考：OSコマンドに渡すパラメータをシェルの環境変数経由で渡す

```bash
hello='hello world'
export hello
echo "$hello" # hello world
```

```
シェルスクリプト内では、 環境変数を受け取る(変数展開)ときにダブルクォートすることが重要です。 ダブルクォート内で展開されたパラメーターはパス名展開やワード分割などの対象とならないため、そのままの値がコマンドの引数に渡されます。

https://fumiyas.github.io/2013/12/21/dont-use-shell.sh-advent-calendar.html
```
ダブルクオートでくくると、コマンドに渡されるパラメータはただの文字列になる。安全。


```php
<?php
// $mailはpostで受け取る
$descriptorspec = array(0 => array('pipe', 'r'));
$env = array('e_mail' => $mail);
// sendmailコマンドに渡すメールアドレスを"e_mail"として環境変数に入れる
$process = proc_open('/usr/sbin/sendmail -i "$e_mail"', $descriptorspec, $pipes, $getcwd(), $env);
// 引数の最後にわたしている$envが環境変数。って、これ環境変数と呼んでいいんか？
// putenvとかで設定して読み込むのかと思ってたけどちょっと違う？
```

### OSコマンド・インジェクション攻撃への保険的対策
* パラメータの検証
* アプリケーションの可動する権限を最小限にする
* WebサーバのOSのミドルウェアのパッチ適用

#### パラメータの検証
OSコマンドのパラメータにファイル名を渡している場合、
ファイル名の要件を英数字に限定してやる

#### アプリケーションの可動するユーザ権限を最小限にする
Webアプリケーションの権限を必要最低限に制限しておく。

たとえば外部からの攻撃の際に、Webshellと呼ばれる遠隔操作用のバックドアコマンドを
ドキュメントルートにダウンロードして設置する。
よって、ドキュメントルートにWebアプリケーションからの書き込み権限をない状態にすれば、
攻撃は成功しない。

### WebサーバのOSやミドルウェアのパッチ適用
OSの脆弱性をついた攻撃（local exploit）をされると、被害がとても大きくなる。
通常のコマンド実行では、Webサーバが稼働するユーザの権限を超えた被害は出ないが、
内部からの場合は権限昇格の脆弱性をつかれた結果root権限を奪われ、サーバの全ての操作が可能となる可能性。

パッチ適用しよう。

#### 対策（今日の復習）
* phpのSplFileObjectを使えばそもそもシェル呼び出しをする必要もない
* そもそもtest.csvをdocument root上に置く必要は全くない
* apacheの権限をsudo ALLにしない
