#!/bin/bash

# CONFIG ######################################################################

    # TabGeoHack utility
    # https://community.tableau.com/thread/146238

PATH_TABLEAU_REPOSITORY="C:/Users/Andrzej/Documents/My Tableau Repository"

URL_TABGEOHACK="http://www.dropbox.com/s/tbmd5cn47t0jotu/TabGeoHackV2.zip?dl=1"
URL_GDAL="http://www.dropbox.com/s/udve5j19lklaebs/release-1600-gdal-1-9-0-mapserver-6-0-1.zip?dl=1"

    # Official shape files for administrative divisions of Poland:
    # http://www.codgik.gov.pl/index.php/darmowe-dane/prg.html

URL_SHAPEFILES="ftp://91.223.135.109/prg/jednostki_administracyjne.zip"

    # Poczta Polska list of post-office box numbers

URL_PP_POBN="https://www.poczta-polska.pl/hermes/uploads/2017/04/wykaz_czynnych_plac%C3%B3wek_skrytki_stan_na_31_03_2017.xlsx"

    # R checkpoint library snapshot date
    
export R_CHECKPOINT_SNAPSHOT_DATE="2017-03-15"

    # Add extra Tableau zipcodes that are not in Poczta Polska official zipcode list

export ADD_TABLEAU_ZIPCODES_TO_PP=1

###############################################################################

export DIR_DOWNLOADS="downloads"
export DIR_GEN="gen"
export DIR_SHAPEFILES="shapes"
export DIR_TABGEOHACK="tabgeohack"

ZIP_SHAPEFILES="shapes.zip"
ZIP_TABGEOHACK="tabgeohack.zip"
ZIP_GDAL="gdal.zip"

export FILE_POBN="pl-pobn.xlsx"
export GEN_AD="pl-ad-all.csv"
export GEN_ZC_POBN="pl-zipcodes-pobn.csv"
export GEN_ZC_CRAWLED="pl-zipcodes-crawled.csv"
export GEN_ZC_TABLEAU="pl-zipcodes-tableau.csv"
export GEN_AD_WITH_ZC="pl-ad-all-with-zipcodes.csv"
export GEN_AD_ZC_LOOKUP="pl-ad-zipcodes-lookup.csv"

R_FILE_SCRIPT="funcs.R"

YML_TGH_MAIN="tgh-main.yml"
YML_TGH_SHAPES="tgh-shapes.yml"

#############################################################################

function check-requirements {

    echo "Checking requirements..."

    PKG_ARR=(build-essential libproj-dev libgeos-dev libgdal-dev)
    PKG_R_FLAG=0

    for pkgname in ${PKG_ARR[@]}; do
            dpkg-query -l $pkgname &> /dev/null
            if [ $? -ne 0 ] ; then
                echo "Missing package: $pkgname"; PKG_R_FLAG=1
            fi
    done

    Rscript -e "TRUE" &> /dev/null
    if [ $? -ne 0 ] ; then
        echo "Missing R"; PKG_R_FLAG=1
    fi
    
    if [ $PKG_R_FLAG -ne 0 ] ; then
        exit 1
    fi

    Rscript -e "library(checkpoint)" &> /dev/null
    if [ $? -ne 0 ] ; then
        echo "Missing R checkpoint library"; exit 1
    fi
    
    Rscript -e "library(checkpoint); checkpoint('$R_CHECKPOINT_SNAPSHOT_DATE', verbose = TRUE, scanForPackages = TRUE)"
    if [ $? -ne 0 ] ; then
        echo "Installation of R libraries failed"; exit 1
    fi

    echo "OK"
}

function get-shapefiles {

    echo "Downloading shape files..."

    curl --create-dirs -o $DIR_DOWNLOADS/$ZIP_SHAPEFILES $URL_SHAPEFILES
    
    echo "Done"
}

function process-shapefiles {

    echo "Processing shape files..."
    echo " * extract voivodeships, counties and communes"
    
    unzip -qjoU $DIR_DOWNLOADS/$ZIP_SHAPEFILES -x "PRG*/jedn*" "PRG*/obreby*" "PRG*/Pa*" "PRG*/*.lock" -d $DIR_SHAPEFILES

    echo " * fix escaped Unicode characters for 'o'"
    
    find $DIR_SHAPEFILES -depth -name "*#U00f3*" -execdir bash -c 'mv -i "$1" "${1//#U00f3/o}" --force' bash {} \;

    echo " * transform shape files to usable form"

    Rscript $R_FILE_SCRIPT $FUNCNAME

    echo "Done"
}

function merge-ad-csv {

    echo "Merging administrative division CSV files..."
    
    Rscript $R_FILE_SCRIPT $FUNCNAME

    echo "Done"
}

function get-tabgeohack {

    echo "Downloading TabGeoHack..."

    curl -L --create-dirs -o $DIR_DOWNLOADS/$ZIP_TABGEOHACK $URL_TABGEOHACK
    curl -L --create-dirs -o $DIR_DOWNLOADS/$ZIP_GDAL $URL_GDAL
    
    echo "Done"
}

function configure-tabgeohack {

    echo "Configuring TabGeoHack..."
    
    echo " * extract files"

    unzip -q $DIR_DOWNLOADS/$ZIP_TABGEOHACK 
    mv TabGeoHackV2 $DIR_TABGEOHACK

    unzip -q $DIR_DOWNLOADS/$ZIP_GDAL -d $DIR_TABGEOHACK/gdal
    
    echo " * copy YAML configs"

    cp $YML_TGH_MAIN $DIR_TABGEOHACK/tabgeohack.yml
    cp $YML_TGH_SHAPES $DIR_TABGEOHACK/
    
    echo " * set Tableau repository path"
    
    sed -i "s|TABLEAU_REPOSITORY_PATH|$PATH_TABLEAU_REPOSITORY|g" $DIR_TABGEOHACK/tabgeohack.yml
    
    echo "Done"
}

function tabgeohack-roles {

    echo "TabGeoHack - processing roles..."
    
    echo " * run TabGeoHack"

    cd $DIR_TABGEOHACK

    ./tabgeohack.exe --roles $YML_TGH_SHAPES

    cd ..
    
    echo " * fix semicolons and encoding"

    sed -i 's/,/;/g' $DIR_TABGEOHACK/out/Custom\ Geocoding\ Files/*

    Rscript $R_FILE_SCRIPT $FUNCNAME
    
    echo "**********"
    echo "1. Run Tableau"
    echo "2. Choose 'Map > Geocoding > Import Custom Geocoding'"
    echo "3. Select '$DIR_TABGEOHACK/out/Custom Geocoding Files/'"
    echo "4. Close Tableau"
    read -p "5. Press [Enter]"

    echo "Done"
}

function tabgeohack-shapes {

    echo "TabGeoHack - processing shapes..."

    cd $DIR_TABGEOHACK

    ./tabgeohack.exe --shapes $YML_TGH_SHAPES

    cd ..

    echo "Tableau custom geocoding files are in ${PATH_TABLEAU_REPOSITORY}/Local Data"
    echo "You can check results by examining 'tests/custom-geocoding.twb' workbook in Tableau"
    
    echo "Done"
}

function get-pp-pob {

    echo "Downloading post-office box numbers for Poczta Polska..."

    curl --create-dirs -o $DIR_DOWNLOADS/$FILE_POBN $URL_PP_POBN
    
    echo "Done"
}

function extract-pp-pobn {

    echo "Extracting post-office box numbers for Poczta Polska..."
    
    Rscript $R_FILE_SCRIPT $FUNCNAME

    echo "Done"
}

function crawl-pp-zipcodes {

    echo "Crawling zipcodes for Poczta Polska..."
    
    Rscript $R_FILE_SCRIPT $FUNCNAME

    echo "Done"
}

function combine-pp {

    if [ $ADD_TABLEAU_ZIPCODES_TO_PP -eq 1 ] ; then
        echo "**********"
        echo "1. Open 'tableau-extra/zipcodes.twb' workbook in Tableau"
        echo "2. Select on map all visible zipcode districts"
        echo "3. Mouse right click > View data... > Full data > Export All"
        echo "4. Save as '$DIR_GEN/$GEN_ZC_TABLEAU'"
        echo "5. Close Tableau"
        read -p "6. Press [Enter]"
    fi
    
    echo "Combining zipcodes with administrative division..."
    
    Rscript $R_FILE_SCRIPT $FUNCNAME
    
    echo "Zipcodes with administrative divisions are in $DIR_GEN/$GEN_AD_WITH_ZC"

    echo "Done"
}

function make-zipcodes-lookup {

    if [ ! -f $DIR_GEN/$GEN_ZC_TABLEAU ]; then
        echo "**********"
        echo "1. Open 'tableau-extra/zipcodes.twb' workbook in Tableau"
        echo "2. Select on map all visible zipcode districts"
        echo "3. Mouse right click > View data... > Full data > Export All"
        echo "4. Save as '$DIR_GEN/$GEN_ZC_TABLEAU'"
        echo "5. Close Tableau"
        read -p "6. Press [Enter]"
    fi

    echo "Making Poczta Polska to Tableau zipcode lookup table..."
    
    Rscript $R_FILE_SCRIPT $FUNCNAME
    
    echo "Zipcode lookup table is in $DIR_GEN/$GEN_AD_ZC_LOOKUP"
    echo "You can check results by examining 'tests/pp-zipcodes.twb' workbook in Tableau"

    echo "Done"
}

#############################################################################

if [ $# -eq 0 ]; then
    echo "No arguments supplied"
else
    for i in "$@"
    do  
        $i
    done
fi
