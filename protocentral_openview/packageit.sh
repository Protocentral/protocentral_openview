#!/bin/bash

rm-r *.zip

rm -r application.linux32
rm -r application.linux-armv6hf
rm -r application.linux-arm64
rm -r application.linux-armv6hf

mv application.linux64 pc-openview-linux64
zip -r pc-openview-linux64.zip pc-openview-linux64

mv application.macosx pc-openview-macosx
zip -r pc-openview-macosx.zip pc-openview-macosx

mv application.windows32 pc-openview-windows32
zip -r pc-openview-windows32.zip pc-openview-windows32

mv application.windows64 pc-openview-windows64
zip -r pc-openview-windows64.zip pc-openview-windows64

rm -r -f pc-openview-linux64
rm -r -f pc-openview-macosx
rm -r -f pc-openview-windows32
rm -r -f pc-openview-windows64

