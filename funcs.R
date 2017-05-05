CHECKPOINT.QUICK.LOAD    = TRUE # if TRUE then skip testing https and checking url
CHECKPOINT.DISABLE.LOG   = TRUE
CHECKPOINT.MRAN.URL      = "http://mran.microsoft.com/"
CHECKPOINT.SNAPSHOT.DATE = Sys.getenv("R_CHECKPOINT_SNAPSHOT_DATE")

DIR.DOWNLOADS    = Sys.getenv("DIR_DOWNLOADS")
DIR.GEN          = Sys.getenv("DIR_GEN")
DIR.SHAPEFILES   = Sys.getenv("DIR_SHAPEFILES")
DIR.TABGEOHACK   = Sys.getenv("DIR_TABGEOHACK")
FILE.POBN        = Sys.getenv("FILE_POBN")
GEN.AD           = Sys.getenv("GEN_AD")
GEN.ZC.CRAWLED   = Sys.getenv("GEN_ZC_CRAWLED")
GEN.ZC.POBN      = Sys.getenv("GEN_ZC_POBN")
GEN.ZC.TABLEAU   = Sys.getenv("GEN_ZC_TABLEAU")
GEN.AD.WITH.ZC   = Sys.getenv("GEN_AD_WITH_ZC")
GEN.AD.ZC.LOOKUP = Sys.getenv("GEN_AD_ZC_LOOKUP")

ADD.TABLEAU.ZIPCODES.TO.PP = Sys.getenv("ADD_TABLEAU_ZIPCODES_TO_PP")

###############################################################################

args = commandArgs(trailingOnly=TRUE)

if (length(args) != 1)
{
    stop("One argument must be supplied")
}

###############################################################################

load.checkpoint = function()
{
    suppressPackageStartupMessages({
        library(checkpoint)
    })

    if (CHECKPOINT.DISABLE.LOG)
    { 
        try({assignInNamespace("checkpoint_log", function(...) {}, "checkpoint")}, 
            silent = TRUE)
    }

    if (CHECKPOINT.QUICK.LOAD) # approx. x10 faster checkpoint library loading
    {
        # assume https
        options(checkpoint.mranUrl = CHECKPOINT.MRAN.URL)
        # disable url checking
        assignInNamespace("is.404", function(mran, warn = TRUE) { FALSE },
                          "checkpoint")
    }

    checkpoint(CHECKPOINT.SNAPSHOT.DATE, verbose = FALSE, scanForPackages = FALSE)
}

process.shapefiles = function()
{
    cfg = list("gminy"       = c("Gmi_ID", "Gmi_kodGUS", "Gmi_nazwa"),
               "powiaty"     = c("Pow_ID", "Pow_kodGUS", "Pow_nazwa"),
               "wojewodztwa" = c("Woj_ID", "Woj_kodGUS", "Woj_nazwa"))


    for (i in 1:length(cfg))
    {
        area.name = names(cfg[i])
        area.cfg  = cfg[[i]]

        area = rgdal::readOGR(DIR.SHAPEFILES, area.name, use_iconv = TRUE, encoding = "CP1250")

        area = area[, c("iip_identy", "jpt_kod_je", "jpt_nazwa_")]
        names(area) = area.cfg
        area@data[, 1] = paste0(area@data[, 1], "-", area@data[, 2])

        if (area.name == "gminy")
        {
            area@data$Gmi_rodz = sapply(area@data$Gmi_kodGUS, function(x){
                v = substr(as.character(x), 7, 7)
                if (v == "1")
                    return("miejska")
                else if (v == "2")
                    return("wiejska")
                else if (v == "3")
                    return("miejsko-wiejska")
                else
                    stop("Unknown type")
            })
        }

        if (area.name == "powiaty")
            area@data$Pow_nazwa = gsub("^powiat ", "", area@data$Pow_nazwa)
            
        area_new.sp   = unionSpatialPolygons(area, area[[area.cfg[1]]])

        area_new.data = unique(area@data)
        rownames(area_new.data) = area_new.data[[area.cfg[1]]]
        
        area_new = SpatialPolygonsDataFrame(area_new.sp, area_new.data)

        setCPLConfigOption("SHAPE_ENCODING", "UTF-8")
        rgdal::writeOGR(area_new, DIR.SHAPEFILES, area.name, "ESRI Shapefile",
                        layer_options = c(encoding = "UTF-8"), overwrite_layer = TRUE)

        fwrite(area_new@data, paste0(DIR.GEN, "/pl-ad-", area.name, ".csv"), sep = ";")
    }
}

merge.ad.csv = function()
{
    df.gminy       = read.csv2(paste0(DIR.GEN, "/pl-ad-gminy.csv"), fileEncoding = "utf-8", colClasses = "character")
    df.powiaty     = read.csv2(paste0(DIR.GEN, "/pl-ad-powiaty.csv"), fileEncoding = "utf-8", colClasses = "character")
    df.wojewodztwa = read.csv2(paste0(DIR.GEN, "/pl-ad-wojewodztwa.csv"), fileEncoding = "utf-8", colClasses = "character")

    df.gminy       = df.gminy %>% select(-Gmi_ID) %>% mutate(Woj_kodGUS = substr(Gmi_kodGUS, 0, 2), Pow_kodGUS = substr(Gmi_kodGUS, 0, 4))
    df.powiaty     = df.powiaty %>% select(-Pow_ID) %>% mutate(Woj_kodGUS = substr(Pow_kodGUS, 0, 2))
    df.wojewodztwa = df.wojewodztwa %>% select(-Woj_ID)

    df.merged = left_join(df.gminy, left_join(df.powiaty, df.wojewodztwa, by = "Woj_kodGUS"), by = c("Woj_kodGUS", "Pow_kodGUS"))
    df.merged = df.merged %>% select(Woj_kodGUS, Pow_kodGUS, Gmi_kodGUS, Woj_nazwa, Pow_nazwa, Gmi_nazwa, Gmi_rodz) %>% arrange(Gmi_kodGUS)

    fwrite(df.merged, paste0(DIR.GEN, "/", GEN.AD), sep = ";")
}

tabgeohack.roles = function()
{
    # fixing TabGeoHack encoding
    
    x = read.csv2(paste0(DIR.GEN, "/pl-ad-wojewodztwa.csv"), fileEncoding = "utf-8", 
                  check.names = FALSE, colClasses = "character")
    y = read.csv2(paste0(DIR.TABGEOHACK, "/out/Custom Geocoding Files/Wojewodztwo (PL).csv"), 
                  fileEncoding = "utf-8", check.names = FALSE, colClasses = "character")

    y$`Wojewodztwo (PL) - nazwa` = x$Woj_nazwa

    fwrite(y, paste0(DIR.TABGEOHACK, "/out/Custom Geocoding Files/Wojewodztwo (PL).csv"), 
        sep = ";")
}

extract.pp.pobn = function()
{
    df.pp = readxl::read_excel(paste0(DIR.DOWNLOADS, "/", FILE.POBN))
    df.pp = df.pp[, c("Województwo", "Powiat", "Gmina", "Miejscowość", "PNA skrytkowe")]
    colnames(df.pp) = c("Woj_nazwa", "Pow_nazwa", "Gmi_nazwa", "Miejscowosc", "kod")

    df.pp$Woj_nazwa = tolower(df.pp$Woj_nazwa)
    df.pp = df.pp[!is.na(df.pp$kod), ]
    df.pp = unique(df.pp)

    fwrite(df.pp, paste0(DIR.GEN, "/", GEN.ZC.POBN), sep = ";")
}

crawl.pp.zipcodes = function()
{
    PP.URL = "http://kody.poczta-polska.pl/index.php?p={PAGE}&kod={ZIPCODE}&page=kod"
    
    ZIPCODES = sort(apply(expand.grid(0:9, 0:9, 0:9, 0:9, 0:9), 1, 
                 function(x) {paste0(x[1],x[2],x[3],x[4],x[5])}))
                 
    cat(" * running rvest (this may take a while)", fill = TRUE)

    if (Sys.info()[['sysname']] == "Linux")
	{
		cat(" * cluster logs and task status: /tmp/r-cluster.log", fill = TRUE)
	}
				 
	cl = makeCluster(parallel::detectCores(), outfile = ifelse(Sys.info()[['sysname']] == "Linux", "/tmp/r-cluster.log", ""))
    registerDoParallel(cl)
    clusterCall(cl, function(x) .libPaths(x), .libPaths())

    df.download = foreach(zipcode = ZIPCODES, .combine = rbind, .packages = c("rvest", "curl")) %dopar%
    {
        df.ret = data.frame()
        current.page = 0
        
        while(TRUE)
        {
            current.url = gsub("\\{ZIPCODE\\}", zipcode, 
                        gsub("\\{PAGE\\}", current.page, PP.URL))
            
            print(current.url)
                        
            MAX.RETRY = 5

            no.retry = MAX.RETRY
            html.file = NULL

            while (is.null(html.file) & no.retry > 0)
            {
                tryCatch(
                    {
                        con <- curl(current.url, 
                                    handle = new_handle(TIMEOUT = 15))
                        html.file <- read_html(con, encoding = "utf8")
                    },
                    error = function(e) { 
                        warning(paste(e$message, "-", current.url, "- attempt:", 
                                      MAX.RETRY + 1 - no.retry), immediate. = TRUE)
                        close(con)
                        }
                )
                
                if (is.null(html.file))
                {
                    no.retry = no.retry - 1
                }
            }

            if (is.null(html.file))
            {
                stop(paste("Unable to connect", current.url))
            }
            
            if (grepl("Zapytanie nie zwróciło wyników", 
                      html_text(html.file), fixed = TRUE))
            {
                break
            }
            
            if (grepl("Zapytanie zwróciło zbyt wiele wyników (ponad 600)", 
                      html_text(html.file), fixed = TRUE))
            {
                warning(paste("Too many records:", current.url))
                break
            }
            
            tables = html_nodes(html.file, "table")

            if (length(tables) == 0)
            {
                break
            }
            
            if (length(tables) > 1)
            {
                stop("Tables > 1")
            }
            
            table1 = html_table(tables[1][[1]], fill = TRUE)
          
            if (nrow(table1) == 0)
            {
                break
            }
            
            df.ret = rbind(df.ret, table1)
            
            if (nrow(table1) == 50)
            {
                current.page = current.page + 1
            } else {
                break
            }
        }

        return(df.ret)
    }
    
    stopCluster(cl)

    df.download = df.download[, c("województwo", "powiat", "gmina", "miejscowość", "kod PNA")]
    colnames(df.download) = c("Woj_nazwa", "Pow_nazwa", "Gmi_nazwa", "Miejscowosc", "kod")
    df.download$Woj_nazwa = tolower(df.download$Woj_nazwa)

    fwrite(unique(df.download), paste0(DIR.GEN, "/", GEN.ZC.CRAWLED), sep = ";")
}

combine.pp = function()
{
    df.pp.pbo  = read.csv2(paste0(DIR.GEN, "/", GEN.ZC.POBN), fileEncoding = "utf-8", colClasses = "character")
    df.pp.down = read.csv2(paste0(DIR.GEN, "/", GEN.ZC.CRAWLED), fileEncoding = "utf-8", colClasses = "character")
    df.ad.gpw  = read.csv2(paste0(DIR.GEN, "/", GEN.AD), fileEncoding = "utf-8", colClasses = "character")

    df.pp = unique(rbind(df.pp.down, df.pp.pbo))
    
    cat(" * fix Poczta Polska locality names", fill = TRUE)

    df.pp[with(df.pp, Woj_nazwa == "mazowieckie" & Pow_nazwa == "Warszawa" &
                   Gmi_nazwa == "Warszawa"), "Miejscowosc"] = "Warszawa"

    df.pp[with(df.pp, Woj_nazwa == "małopolskie" & Pow_nazwa == "Kraków" &
                   Gmi_nazwa == "Kraków"), "Miejscowosc"] = "Kraków"

    df.pp[with(df.pp, Woj_nazwa == "łódzkie" & Pow_nazwa == "Łódź" &
                   Gmi_nazwa == "Łódź"), "Miejscowosc"] = "Łódź"

    df.pp[with(df.pp, Woj_nazwa == "wielkopolskie" & Pow_nazwa == "Poznań" &
                   Gmi_nazwa == "Poznań"), "Miejscowosc"] = "Poznań"

    df.pp[with(df.pp, Woj_nazwa == "dolnośląskie" & Pow_nazwa == "Wrocław" &
                   Gmi_nazwa == "Wrocław"), "Miejscowosc"] = "Wrocław"

    df.pp = unique(df.pp)

    cat(" * fix Poczta Polska commune names", fill = TRUE)

    df.pp[with(df.pp, Woj_nazwa == "świętokrzyskie" & Pow_nazwa == "jędrzejowski" & Gmi_nazwa == "Słupia"), "Gmi_nazwa"] = "Słupia (Jędrzejowska)"
    
    cat(" * fix Poczta Polska zipcodes", fill = TRUE)
    
    df.pp = df[!(df.pp$Miejscowosc == "Hucisko" & df.pp$kod == "72-310"), ]
    
    cat(" * test data equality between Poczta Polska and CODGiK", fill = TRUE)

    test.df.pp     = unique(df.pp[, c("Woj_nazwa", "Pow_nazwa", "Gmi_nazwa")])
    test.df.ad.gpw = unique(df.ad.gpw[, c("Woj_nazwa", "Pow_nazwa", "Gmi_nazwa")])

    if (nrow(test.df.pp) != nrow(test.df.ad.gpw))
    {
        warning("Different length of comb. objects", immediate. = TRUE)
    }

    diff1 = test.df.ad.gpw[!duplicated(rbind(test.df.pp, test.df.ad.gpw))[-seq_len(nrow(test.df.pp))], ]

    diff2 = test.df.pp[!duplicated(rbind(test.df.ad.gpw, test.df.pp))[-seq_len(nrow(test.df.ad.gpw))], ]

    if (nrow(diff1) > 0)
    {
        print(diff1)
        stop("Extra rows in official adm. division list")
    }

    if (nrow(diff2) > 0)
    {
        print(diff2)
        stop("Extra rows in PP zipcode list")
    }

    cat(" * combine datasets (this may take a while)", fill = TRUE)

    if (Sys.info()[['sysname']] == "Linux")
	{
		cat(" * cluster logs and task status: /tmp/r-cluster.log", fill = TRUE)
	}
				 
	cl = makeCluster(parallel::detectCores(), outfile = ifelse(Sys.info()[['sysname']] == "Linux", "/tmp/r-cluster.log", ""))
    registerDoParallel(cl)
    clusterCall(cl, function(x) .libPaths(x), .libPaths())

    df.combined = foreach(i = 1:nrow(df.pp), .combine = rbind, .packages = "plyr") %dopar%
    {
        print(paste(i, "/", nrow(df.pp)))
        row = df.pp[i, ]
        x = plyr::join(row, df.ad.gpw, by = c("Woj_nazwa", "Pow_nazwa", "Gmi_nazwa"))

        if (nrow(x) == 0)
            stop("No matching")

        if (nrow(x) > 2)
            stop("Too many matchings")

        if (nrow(x) == 2)
        {
            x = x[ifelse(row$Miejscowosc == row$Gmi_nazwa,
                         which(x$Gmi_rodz == "miejska"),
                         which(x$Gmi_rodz != "miejska")), ]
        }

        if (any(is.na(x)))
        {
            stop("NA in combined row")
        }

        x
    }

    stopCluster(cl)
    
    if (ADD.TABLEAU.ZIPCODES.TO.PP == "1")
    {
        cat(" * add extra Tableau zipcodes", fill = TRUE)
    
        df.tableau = read.csv2(paste0(DIR.GEN, "/", GEN.ZC.TABLEAU), fileEncoding = "utf-8", colClasses = "character")
    
        tmp = as.numeric(gsub("-", "", df.combined$kod))
        zc.t = df.tableau$kod[which(!(df.tableau$kod %in% df.combined$kod))]

        zc.tn = df.combined[sapply(as.numeric(gsub("-", "", zc.t)), function(x) {
            which.min(abs(x - tmp))[1]
        }), ]

        zc.tn$kod = zc.t

        df.combined = rbind(df.combined, zc.tn)
    }

    cat(" * finalize", fill = TRUE)

    fwrite(df.combined, paste0(DIR.GEN, "/", GEN.AD.WITH.ZC), sep = ";")
}

make.zipcodes.lookup = function()
{
    zc.tableau = sort(unique(read.csv2(paste0(DIR.GEN, "/", GEN.ZC.TABLEAU), fileEncoding = "utf-8", colClasses = "character")$kod))
    zc.pp      = sort(unique(read.csv2(paste0(DIR.GEN, "/", GEN.AD.WITH.ZC), fileEncoding = "utf-8", colClasses = "character")$kod))

    tmp = as.numeric(gsub("-", "", zc.tableau))

    zc.lkp = sapply(as.numeric(gsub("-", "", zc.pp)), function(x) {
        zc.tableau[which.min(abs(x - tmp))[1]]
    })

    df.lookup = data.frame(kod.pp = zc.pp, kod.tableau = zc.lkp)

    fwrite(df.lookup, paste0(DIR.GEN, "/", GEN.AD.ZC.LOOKUP), sep = ";")

}

###############################################################################

load.checkpoint()

suppressPackageStartupMessages({
    library(data.table)
    library(rgdal)
    library(rgeos)
    library(maptools)
    library(doParallel)
    library(plyr)
    library(dplyr)
    library(readxl)
    library(foreach)
    library(rvest)
    library(curl)
})

if (!dir.exists(DIR.GEN))
{
    dir.create(DIR.GEN)
}

func.to.run = get(gsub("-", ".", args[1]))
func.to.run()
