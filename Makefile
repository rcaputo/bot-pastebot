VERSION=20021017
DISTNAME=pastebot-$(VERSION)
DISTBUILD=$(DISTNAME)
DISTTAR=$(DISTNAME).tar
DISTTGZ=$(DISTTAR).gz

dist: $(DISTTGZ)

$(DISTTGZ): distdir
	if [ -e $(DISTTGZ) ] ; \
	  then echo $(DISTTGZ) already exists ; \
	       exit 1 ; \
	fi
	tar cf $(DISTTAR) $(DISTBUILD)
	-perl -MExtUtils::Command -e rm_rf $(DISTBUILD)
	gzip $(DISTTAR)

distdir:
	-perl -MExtUtils::Command -e rm_rf $(DISTBUILD)
	perl -MExtUtils::Manifest=manicopy,maniread -e "manicopy(maniread(), '$(DISTBUILD)')"
	find $(DISTBUILD) -type f | xargs chmod u+w

clean:
	-perl -MExtUtils::Command -e rm_rf $(DISTBUILD)

manicheck:
	perl -MExtUtils::Manifest=manicheck -e 'manicheck()'

filecheck:
	perl -MExtUtils::Manifest=filecheck -e 'filecheck()'

mkmanifest:
	perl -MExtUtils::Manifest=mkmanifest -e 'mkmanifest()'
