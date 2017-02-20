FROM nginx:alpine
MAINTAINER Steve Buzonas <steve@fancyguy.com>

LABEL com.fancyguy.os.flavor="linux" \
      com.fancyguy.os.distro="Alpine" \
      com.fancyguy.project="analytics" \
      com.fancyguy.team="operations" \
      com.fancyguy.frontend="nginx" \
      com.fancyguy.backend="php-fpm"

# Changing any of these should rebuild everything
ENV PHP_VERSION="7.1.2" \
    PHP_PREFIX="/opt/php"
ENV PHP_INI_DIR="$PHP_PREFIX/etc" \
    PHP_SOURCES="$PHP_PREFIX/src"
ENV PHP_DEFAULT_SCAN_DIR="$PHP_INI_DIR/conf.d"

ENV DUMB_INIT_VERSION=1.1.2
ENV PYTHON_VERSION=2.7.12-r0
ENV SUPERVISOR_VERSION=3.3.0

# Build everything except for PHP
RUN apk add --no-cache \
    	ca-certificates \
	curl \
	py-pip \
        python=$PYTHON_VERSION \
	tar \
	xz && \
    pip install --no-cache-dir supervisor==$SUPERVISOR_VERSION && \
    mkdir -p /usr/local/sbin && \
    wget -O /usr/local/sbin/dumb-init https://github.com/Yelp/dumb-init/releases/download/v${DUMB_INIT_VERSION}/dumb-init_${DUMB_INIT_VERSION}_amd64 && \
    chmod +x /usr/local/bin/dumb-init && \
    addgroup -g 82 -S www-data && \
    adduser -u 82 -D -S -G www-data www-data && \
    # 82 is the standard uid/gid for "www-data" in Alpine
    rm -rf /var/cache/apk/*

### Sources

# Source tarball configuration
ENV PHP_URL="https://secure.php.net/get/php-${PHP_VERSION}.tar.xz/from/this/mirror" \
    PHP_ASC_URL="https://secure.php.net/get/php-${PHP_VERSION}.tar.xz.asc/from/this/mirror" \
    PHP_SHA256="d815a0c39fd57bab1434a77ff0610fb507c22f790c66cd6f26e27030c4b3e971" \
    PHP_MD5="d79afea1870277c86fac903566fb6c5d" \
    PHP_GPG_KEYS="A917B1ECDA84AEC2B568FED6F50ABC807BD5DCD0 528995BFEDFBA7191D46839EF9BA0ADA31CBD89E"

# Fetch and verify
RUN apk add --no-cache --virtual .fetch-deps \
        gnupg \
	openssl && \
    mkdir -p $PHP_PREFIX && \
    cd $PHP_PREFIX && \
    echo -e "==> Downloading PHP ${PHP_VERSION} Sources..." && \
    wget -O php.tar.xz "$PHP_URL" && \
    echo "==> Verifying source integrity..." && \
    { echo "$PHP_SHA256 *php.tar.xz" | sha256sum -c -; } && echo "==> SHA256 Checksum Passed" \
        || { echo "==> SHA256 Checksum Failed" >/dev/stderr; exit 1; } && \
    { echo "$PHP_MD5 *php.tar.xz" | md5sum -c -; } && echo "==> MD5 Checksum Passed" \
        || { echo "==> MD5 Checksum Failed" >/dev/stderr; exit 1; } && \
    echo "==> Verifying release signature..." && \
    wget -O php.tar.xz.asc "$PHP_ASC_URL" && \
    export GNUPGHOME="$(mktemp -d)" && \
    for key in $PHP_GPG_KEYS; do \
        gpg --keyserver ha.pool.sks-keyservers.net --recv-keys "$key"; \
    done && \
    gpg --batch --verify php.tar.xz.asc php.tar.xz && echo "==> Signature check passed" \
        || { echo "==> Signature check failed" >/dev/stderr; exit 1; } && \
    rm -r $GNUPGHOME && \
    apk del .fetch-deps && \
    rm -rf /var/cache/apk/*

### Compile the PHP runtime

## Compiler Options
# Apply stack smash protection, compile the executable to be position independent
# Move invariant conditions out of loops, reuse computations within loops
# Optimize the binary for size, use pipes instead of temp files to speed up compile
## TODO: Consider math optimizations, are they available for all targets? Can ISO/IEEE math specs be ignored?
## Linker Options
# Enable optimization
# Add GNU HASH segments (faster than sysv)
ENV PHP_CFLAGS="-fstack-protector-strong -fpic -fpie -Os -funswitch-loops -fpredictive-commoning" PHP_CPPFLAGS="$PHP_CFLAGS" PHP_LDFLAGS="-Wl,-O1 -Wl,--hash-style=both -pie"

# Configure args
ENV PHP_EXTRA_CONFIGURE_ARGS=""

# Extract, configure, compile, cleanup

ENV PHPIZE_DEPS \
        autoconf \
	file \
	g++ \
	gcc \
	libc-dev \
	make \
	pkgconf \
	re2c

RUN mkdir -p $PHP_SOURCES && \
    tar -Jxf $PHP_PREFIX/php.tar.xz -C $PHP_SOURCES --strip-components=1 && \
    mkdir -p $PHP_DEFAULT_SCAN_DIR && \
    apk add --no-cache --virtual .build-deps \
    	$PHPIZE_DEPS \
	bzip2-dev \
	curl-dev \
	freetype-dev \
	gettext-dev \
	gmp-dev \
	icu-dev \
	imap-dev \
	jpeg-dev \
	krb5-dev \
	libedit-dev \
	libpng-dev\
	libxml2-dev \
	libxslt-dev \
	openldap-dev \
	openssl-dev \
	postgresql-dev \
	sqlite-dev && \
    export CFLAGS="$PHP_CFLAGS" \
    	   CPPFLAGS="$PHP_CPPFLAGS" \
	   LDFLAGS="$PHP_LDFLAGS" && \
    cd $PHP_SOURCES && \
    echo "==> Configuring PHP..." && \
    ./configure \
        --prefix=$PHP_PREFIX \
        --with-config-file-path="$PHP_INI_DIR" \
	--with-config-file-scan-dir="$PHP_DEFAULT_SCAN_DIR" \
	\
	--disable-cgi \
	--enable-fpm \
	--with-fpm-user=www-data \
	--with-fpm-group=www-data \
	\
	--enable-mbstring \
	--enable-mysqlnd \
	\
	--with-bz2 \
	--with-curl \
	--with-libedit \
	--with-pdo-mysql \
	--with-mysqli \
	--with-openssl \
	    --with-kerberos \
	--with-pgsql \
	--with-pdo-pgsql \
	--with-readline \
	--enable-sockets \
	--enable-zip \
	--with-zlib \
	\
	--enable-bcmath=shared \
	--enable-calendar=shared \
	--enable-exif=shared \
	--enable-ftp=shared \
	--with-gd=shared \
	    --enable-gd-native-ttf \
	    --with-freetype-dir=/usr \
	    --with-jpeg-dir=/usr \
	    --with-png-dir=/usr \
	--with-gettext=shared \
	--with-gmp=shared \
	--with-imap=shared,${PHP_PREFIX}/opt/imap-2007f \
	    --with-imap-ssl \
	--enable-intl=shared \
	--with-ldap=shared \
	    --with-ldap-sasl \
	--enable-mbstring=shared \
	--enable-pcntl=shared \
	--enable-shmop=shared \
	--enable-soap=shared \
	--with-sqlite3=shared \
	--with-pdo-sqlite=shared \
	--with-xmlrpc=shared \
	--with-xsl=shared \
	\
	$PHP_EXTRA_CONFIGURE_ARGS && \
    echo "==> Building PHP..." && \
    readonly NPROC=$(grep -c ^processor /proc/cpuinfo 2>/dev/null || 1) && \
    echo "using upto $NPROC threads" && \
    make -j${NPROC} && \
    echo "==> Installing PHP..." && \
    make install && \
    ln -sf $PHP_PREFIX/bin/php /usr/local/bin/php && \
    ln -sf $PHP_PREFIX/sbin/php-fpm /usr/local/sbin/php-fpm && \
    echo "==> Stripping symbols..." && \
    { find $PHP_PREFIX/bin $PHP_PREFIX/sbin -type f -perm +0111 -exec strip --strip-all '{}' + || true; } && \
    echo "==> Cleaning up..." && \
    make clean && \
    cd $PHP_PREFIX && \
    rm -rf $PHP_SOURCES && \
    runtimeDeps="$( \
        scanelf --needed --nobanner --recursive $PHP_PREFIX \
	| awk '{ gsub(/,/, "\nso:", $2); print "so:" $2 }' \
	| sort -u \
	| xargs -r apk info --installed \
	| sort -u \
    )" && \
    apk add --no-cache --virtual .php-rundeps $runtimeDeps && \
    apk del .build-deps && \
    rm -rf /var/cache/apk/*

EXPOSE 80 443
WORKDIR $PHP_PREFIX/

COPY supervisord.conf /etc/supervisord.conf

CMD ["dumb-init", "supervisord", "-c", "/etc/supervisord.conf"]
