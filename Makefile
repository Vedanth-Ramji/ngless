VERSION=1.0

progname=ngless

prefix=/usr/local
deps=$(prefix)/share/$(progname)
exec=$(prefix)/bin

all: compile

BWA = bwa-0.7.7
BWA_URL = http://sourceforge.net/projects/bio-bwa/files/bwa-0.7.7.tar.bz2
BWA_DIR = bwa-0.7.7.tar.bz2

SAM = samtools-1.0
SAM_URL = http://sourceforge.net/projects/samtools/files/samtools/1.0/samtools-1.0.tar.bz2
SAM_DIR = samtools-1.0.tar.bz2

HTML = Html
HTML_LIBS_DIR = $(HTML)/htmllibs
HTML_FONTS_DIR = $(HTML)/fonts

# Required html Librarys
HTMLFILES := jquery-latest.min.js
HTMLFILES += angular.min.js
HTMLFILES += bootstrap.min.css
HTMLFILES += bootstrap-theme.min.css
HTMLFILES += bootstrap.min.js
HTMLFILES += d3.min.js
HTMLFILES += nv.d3.js
HTMLFILES += nv.d3.css
HTMLFILES += angular-sanitize.js
HTMLFILES += bootstrap-glyphicons.css
HTMLFILES += ng-table.js
HTMLFILES += ng-table.css
HTMLFILES += angular-ui-router.min.js
HTMLFILES += angular-animate.min.js
HTMLFILES += ace.js
HTMLFILES += mode-python.js

# Required fonts
FONTFILES := glyphicons-halflings-regular.woff
FONTFILES += glyphicons-halflings-regular.ttf

#URLS
jquery-latest.min.js = code.jquery.com/jquery-latest.min.js 
d3.min.js = cdnjs.cloudflare.com/ajax/libs/d3/3.1.6/d3.min.js
nv.d3.js = cdnjs.cloudflare.com/ajax/libs/nvd3/1.1.14-beta/nv.d3.js
nv.d3.css = cdnjs.cloudflare.com/ajax/libs/nvd3/1.1.14-beta/nv.d3.css
ng-table.js = bazalt-cms.com/assets/ng-table/0.3.0/ng-table.js
ng-table.css = bazalt-cms.com/assets/ng-table/0.3.0/ng-table.css
angular-sanitize.js = code.angularjs.org/1.3.0-beta.1/angular-sanitize.js
bootstrap.min.js = netdna.bootstrapcdn.com/bootstrap/3.0.2/js/bootstrap.min.js
bootstrap.min.css = netdna.bootstrapcdn.com/bootstrap/3.0.2/css/bootstrap.min.css
angular.min.js = ajax.googleapis.com/ajax/libs/angularjs/1.3.0-beta.1/angular.min.js
bootstrap-glyphicons.css += netdna.bootstrapcdn.com/bootstrap/3.0.0/css/bootstrap-glyphicons.css
bootstrap-theme.min.css = netdna.bootstrapcdn.com/bootstrap/3.0.2/css/bootstrap-theme.min.css
glyphicons-halflings-regular.woff = netdna.bootstrapcdn.com/bootstrap/3.0.0/fonts/glyphicons-halflings-regular.woff
glyphicons-halflings-regular.ttf = netdna.bootstrapcdn.com/bootstrap/3.0.0/fonts/glyphicons-halflings-regular.ttf
angular-animate.min.js = ajax.googleapis.com/ajax/libs/angularjs/1.2.16/angular-animate.min.js
angular-ui-router.min.js = cdnjs.cloudflare.com/ajax/libs/angular-ui-router/0.2.10/angular-ui-router.min.js
ace.js = cdnjs.cloudflare.com/ajax/libs/ace/1.1.3/ace.js
mode-python.js = cdnjs.cloudflare.com/ajax/libs/ace/1.1.3/mode-python.js

GIT-LOGO += github-media-downloads.s3.amazonaws.com/Octocats.zip

reqhtmllibs = $(addprefix $(HTML_LIBS_DIR)/, $(HTMLFILES))
reqfonts = $(addprefix $(HTML_FONTS_DIR)/, $(FONTFILES))
reqlogo = $(HTML_LIBS_DIR)/Octocat.png
#

test: compile
	cp dist/build/nglesstest/nglesstest .
	cd test_samples/; gzip -dkf *.gz;
	cd test_samples/htseq-res/; ./generateHtseqFiles.sh
	./nglesstest

install: install-dir install-html install-bwa install-sam
#	cp dist/build/nglesstest/nglesstest $(exec)/nglesstest
	cp -f dist/build/ngless/ngless $(exec)/ngless

install-html:
	cp -rf $(HTML) $(deps)

install-bwa:
	cp -rf $(BWA) $(deps)

install-sam:
	cp -rf $(SAM) $(deps)

install-dir:
	mkdir -p $(exec)
	mkdir -p $(deps);

compile: nglessconf
	cabal build


nglessconf: cabal.sandbox.config htmldirs  $(SAM) $(BWA) $(reqhtmllibs) $(reqfonts) $(reqlogo)

cabal.sandbox.config:
	cabal sandbox init
	cabal install --only-dependencies --force-reinstalls

clean:
	rm -rf dist

clean-sandbox:
	cabal sandbox delete

clean-tests:
	rm test_samples/htseq-res/*.txt

variables:
	@echo $(BWA)
	@echo $(prefix)
	@echo $(deps)
	@echo $(exec)
	@echo $(HTML_LIBS_DIR)
	@echo $(HTML_FONTS_DIR)


uninstall:
	rm -rf $(deps) $(exec)/ngless* $(HOME)/.ngless


#####  Setup required files
htmldirs:
	mkdir -p $(HTML_FONTS_DIR)
	mkdir -p $(HTML_LIBS_DIR)

$(BWA):
	@echo Configuring BWA...
	wget $(BWA_URL)
	tar xvfj $(BWA_DIR)
	rm $(BWA_DIR)
	cd $(BWA); $(MAKE)

$(SAM): 
	@echo Configuring SAM...
	wget $(SAM_URL)
	tar xvfj $(SAM_DIR)
	rm $(SAM_DIR)
	cd $(SAM); $(MAKE)
	@echo Sam tools completed...


$(HTML_LIBS_DIR)/%.js: 
	echo $(notdir $@)
	wget -O $@ $($(notdir $@))


$(HTML_LIBS_DIR)/%.css:
	echo $(notdir $@)
	wget -O $@ $($(notdir $@))


$(HTML_FONTS_DIR)/%.woff:
	echo $(notdir $@)
	wget -O $@ $($(notdir $@))

$(HTML_FONTS_DIR)/%.ttf:
	echo $(notdir $@)
	wget -O $@ $($(notdir $@))

$(HTML_LIBS_DIR)/Octocat.png:
	wget -O $(HTML_LIBS_DIR)/$(notdir $(GIT-LOGO)) $(GIT-LOGO);
	unzip $(HTML_LIBS_DIR)/$(notdir $(GIT-LOGO)) -d $(HTML_LIBS_DIR);
	cp $(HTML_LIBS_DIR)/Octocat/Octocat.png $(HTML_LIBS_DIR)/Octocat.png;
	rm -rf $(HTML_LIBS_DIR)/__MACOSX $(HTML_LIBS_DIR)/Octocat $(HTML_LIBS_DIR)/Octocats.zip;
	echo $(GIT-LOGO) configured;


######


#Generate self-contained executables
64-MAC-PATH := 64-Mac

64x-macos: nglessconf
	mkdir -p $(64-MAC-PATH)/share $(64-MAC-PATH)/bin
	cabal build
	cp dist/build/$(progname)/$(progname) $(64-MAC-PATH)/bin
	cp -r $(BWA) $(64-MAC-PATH)/share
	cp -r $(SAM) $(64-MAC-PATH)/share
	cp -r $(HTML) $(64-MAC-PATH)/share
	tar -zcvf $(64-MAC-PATH).tar.gz $(64-MAC-PATH)
	rm -rf $(64-MAC-PATH)

#########
