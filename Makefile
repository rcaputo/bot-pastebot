VERSION=20040908
DISTNAME=pastebot-$(VERSION)
DISTBUILD=$(DISTNAME)
DISTTAR=$(DISTNAME).tar
DISTTGZ=$(DISTTAR).gz

prefix      = /usr/local
datadir	    = $(prefix)/share
exec_prefix = $(prefix)
man_prefix  = $(prefix)/share
sysconfdir  = $(prefix)/etc

INSTALL         = /usr/bin/install
INSTALL_BIN     = -m 755
INSTALL_DATA    = -m 644

PACKAGE		= pastebot

BINFILE         = $(PACKAGE)
BINSRC          = $(PACKAGE).perl

CONFSRC 	= $(PACKAGE).conf-dist
CONFFILE	= $(PACKAGE).conf

LIBSRC          = $(PACKAGE).lib.sample
LIBFILE         = $(PACKAGE).lib

BINDIR      = $(exec_prefix)/bin
MANDIR      = $(man_prefix)/man/man1
DATADIR     = $(datadir)/$(PACKAGE)
PASTEDIR    = $(datadir)/$(PACKAGE)/pastestore
ETCDIR	    = $(sysconfdir)/$(PACKAGE)

TAR_OPT_EX  = --exclude=CVS --exclude=*[~\#] --exclude *.conf --exclude *.orig --exclude patch.* --exclude *.bak

dist: $(DISTTGZ)

$(DISTTGZ): distdir
	@if [ -e $(DISTTGZ) ] ; \
	  then echo $(DISTTGZ) already exists ; \
	       exit 1 ; \
	fi
	@tar cf $(DISTTAR) $(DISTBUILD)
	@perl -MExtUtils::Command -e rm_rf $(DISTBUILD)
	@gzip $(DISTTAR)

install-cpan:
	@echo '=== Installing and/or updating CPAN modules...'
	@perl -MCPAN -e '\
	@list = qw( \
	HTTP::Request \
	HTTP::Response \
	HTTP::Status \
        Perl::Tidy \
	POE \
	POE::Component::IRC \
	Storable \
	Text::Template \
	Time::HiRes \
	URI ); \
	install $$_ for @list; \
	'	

install-etc:
	@echo "=== Installing files into $(ETCDIR) ..."
	$(INSTALL) $(INSTALL_BIN) -d $(ETCDIR)
	@if [ ! -d $(ETCDIR) ]; then exit 1; fi
	@if [ -f $(ETCDIR)/$(LIBFILE) ]; then \
	  echo "Not installing, file exists: $(ETCDIR)/$(LIBFILE)"; \
	else	\
	  echo "use lib '$(ETCDIR)';" > $(LIBSRC); \
	  echo "use lib '$(DATADIR)';" >> $(LIBSRC); \
	  echo "1;" >> $(LIBSRC); \
	  $(INSTALL) $(INSTALL_DATA) $(LIBSRC) $(ETCDIR)/$(LIBFILE); \
	fi;
	@if [ -f $(ETCDIR)/$(CONFFILE) ]; then \
	  echo "Not installing, file exists: $(ETCDIR)/$(CONFFILE)"; \
	else	\
	  $(INSTALL) $(INSTALL_DATA) $(CONFSRC) $(ETCDIR)/$(CONFFILE); \
	fi;
	@echo "==="
	@echo "=== You may need to edit files in $(ETCDIR)"
	@echo "==="

install-store:
	@echo "=== Installing pastebot store into $(PASTEDIR) ..."
	$(INSTALL) $(INSTALL_BIN) -d $(PASTEDIR)

install-lib: install-store
	@echo "=== Installing pastebot library into $(DATADIR) ..."
	$(INSTALL) $(INSTALL_BIN) -d $(DATADIR)
	@if [ ! -d $(DATADIR) ]; then exit 1; fi
	@tar $(TAR_OPT_EX) -cf - * | (cd $(DATADIR); tar -xf -)

install-bin: 
	@echo "=== Installing $(BINDIR)/$(BINFILE) ..."
	$(INSTALL) $(INSTALL_BIN) -d $(BINDIR)
	$(INSTALL) $(INSTALL_BIN) $(BINSRC) $(BINDIR)/$(BINFILE)

install: install-lib install-bin install-etc

distdir:
	cvs-log.perl > CHANGES
	@perl -MExtUtils::Command -e rm_rf $(DISTBUILD)
	@perl -MExtUtils::Manifest=manicopy,maniread -e "manicopy(maniread(), '$(DISTBUILD)')"
	@find $(DISTBUILD) -type f | xargs chmod u+w

clean:
	@perl -MExtUtils::Command -e rm_rf $(DISTBUILD) pastebot.lib.sample patch.*
	@find . -name '*~' -delete
	@find . -name '*.orig' -delete
	@find . -name '*.bak' -delete
	@find . -name '.*.swp' -delete

manicheck:
	@perl -MExtUtils::Manifest=manicheck -e 'manicheck()'

filecheck:
	@perl -MExtUtils::Manifest=filecheck -e 'filecheck()'

mkmanifest:
	@perl -MExtUtils::Manifest=mkmanifest -e 'mkmanifest()'
