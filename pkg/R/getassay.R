require(XML)
require(car)

.uniqify <- function(x) {
  u <- unique(x)
  nx <- rep(0, length(x))
  for (i in u) {
    cnt <- length(which(x == i))
    k <- 0
    for (j in 1:length(x)) {
      if (x[j] == i) {
        if (k != 0) {
          nx[j] <- paste(x[j], k, sep='.', collapse='')
        } else {
          nx[j] <- x[j]
        }
        k <- k + 1
      }
    }
  }
  unlist(nx)
}

.gunzip <- function(iname, oname) {
  icon <- gzfile(iname, open='r')
  ocon <- file(oname, open='w')
  while (TRUE) {
    lines <-readLines(icon, n=100)
    if (length(lines) == 0) break
    lines <- paste(lines, sep='', collapse='\n')
    writeLines(lines, con = ocon)
  }
  file.remove(iname)
  close(icon)
  close(ocon)
}

get.assay.desc <- function(aid) {
  descURL <- 'ftp://ftp.ncbi.nlm.nih.gov/pubchem/Bioassay/CSV/Description/'
  url <- paste(descURL,aid,'.descr.xml.gz', sep='', collapse='')  
  tmpdest <- tempfile(pattern = 'adesc')
  tmpdest <- paste(tmpdest, '.gz', sep='', collapse='')

  status <- try(download.file(url, destfile=tmpdest, method='internal', mode='wb', quiet=TRUE),
      silent=TRUE)

  if (class(status) == 'try-error') {
    return(NULL)
  }

  xmlfile <- strsplit(tmpdest, '\\.')[[1]][1]
  .gunzip(tmpdest, xmlfile)
  xml <- xmlTreeParse(xmlfile, asTree=TRUE)
  root <- xmlRoot(xml)

  desc.short <- xmlElementsByTagName(root, 'PC-AssayDescription_name', recursive=TRUE)
  desc.short <- xmlValue(desc.short[[1]])

  desc.comments <- xmlElementsByTagName(root, 'PC-AssayDescription_comment_E', recursive=TRUE)
  desc.comments <- lapply(desc.comments, xmlValue)
  desc.comments <- paste(desc.comments, sep=' ', collapse='')

  result.types <- xmlElementsByTagName(root, 'PC-ResultType', recursive=TRUE)

  type.name <- list()
  type.desc <- list()
  type.unit <- list()
  
  counter <- 1
  repcounter <- 1
  for (aType in result.types) {
    name <- xmlElementsByTagName(aType, 'PC-ResultType_name', recursive=TRUE)
    name <- xmlValue(name[[1]])

    tdesc <- xmlElementsByTagName(aType, 'PC-ResultType_description_E', recursive=TRUE)
    if (length(tdesc) > 0)
      tdesc <- xmlValue(tdesc[[1]])
    else tdesc <- NA

    unit <- xmlElementsByTagName(aType, 'PC-ResultType_unit', recursive=TRUE)

    if (length(unit) != 0) {
      unit <- xmlGetAttr(unit[[1]], name='value')
      if (unit == 'ugml') unit <- 'ug/mL'
      else if (unit == 'm') unit <- 'M'
      else if (unit == 'um') unit <- 'uM'
    } else unit <- 'NA'

    type.name[[counter]] <- name
    type.desc[[counter]] <- tdesc
    type.unit[[counter]] <- unit
    counter <- counter+1
  }

  type.name <- .uniqify(type.name)
  type.info <- data.frame(Name=I(unlist(type.name)),
                          Description=I(unlist(type.desc)),
                          Units=I(unlist(type.unit)))

  unlink(tmpdest)
  
  list(assay.desc=desc.short,
       assay.comments=desc.comments,
       types=type.info)
}


find.assay.id <- function(query, quiet=TRUE) {
  searchURL <- 'http://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi?tool=rpubchem&db=pcassay&term='
  url <- URLencode(paste(searchURL,query,sep='',collapse=''))
  #tmpdest <- tempfile(pattern = 'search')
  tmpdest <- 'srch'

  ## first get the count of results
  status <- try(download.file(url, destfile=tmpdest, method='internal', mode='wb', quiet=quiet),
      silent=TRUE)
  if (class(status) == 'try-error') {
    stop("Couldn't perform search")
  }
  xml <- xmlTreeParse(tmpdest)
  root <- xmlRoot(xml)
  count <- xmlValue(xmlElementsByTagName(root, "Count", recursive=TRUE)[[1]])

  if (count == 0) {
    stop("No assays for this search term")
  }

  ## now get the results
  url <- URLencode(paste(url, '&retmax=', count, sep='', collapse=''))
  status <- try(download.file(url, destfile=tmpdest, method='internal', mode='wb', quiet=quiet),
      silent=TRUE)

  if (class(status) == 'try-error') {
    stop("Couldn't perform search")
  }
  xml <- xmlTreeParse(tmpdest)
  root <- xmlRoot(xml)
  idlist <- xmlElementsByTagName(root, 'IdList', recursive=TRUE)
  if (length(idlist) != 1) {
    stop("Error parsing Entrez output")
  }
  ids <- xmlElementsByTagName(idlist[[1]], 'Id', recursive=TRUE)
  ids <- sort(as.numeric(unlist(lapply(ids, xmlValue))))

  unlink(tmpdest)
  
  ids
}
get.assay <- function(aid, quiet=TRUE) {
  
  baseURL <- 'ftp://ftp.ncbi.nlm.nih.gov/pubchem/Bioassay/CSV/Data/'
  url <- paste(baseURL,aid,'.csv.gz', sep='', collapse='')

  tmpdest <- tempfile(pattern = 'pcassay')
  tmpdest <- paste(tmpdest, '.gz', sep='', collapse='')
  status <- try(download.file(url, destfile=tmpdest, method='internal', mode='wb', quiet=quiet),
      silent=TRUE)

  if (class(status) == 'try-error') {
    stop("Error in the download")
  }
  if (!quiet) cat("Got data file\n")

  csvfile <- strsplit(tmpdest, '\\.')[[1]][1]
    .gunzip(tmpdest, csvfile)

  if (!quiet) cat('Loading data\n')  
  dat <- read.csv(csvfile, header=TRUE)
  dat <- dat[,-c(2,6,8)]

  ## get rid of underscores in the names
  n <- names(dat)
  names(dat) <- gsub('_', '\\.', n)
  
  ## recode the activity outcome column
  f <- recode(dat[,3], "1='inactive'; 2='active'; 3='inconc'; 4='unspec'", as.factor.result=TRUE)
  dat[,3] <- f

  ## lets get the descriptions and set col names and
  ## attributes
  if (!quiet) cat('Processing descriptions\n')
  desc <- get.assay.desc(aid)
  if (is.null(desc)) warning("couldn't get description data'")

  attr(dat, 'description') <- desc$assay.desc
  attr(dat, 'comments') <- desc$assay.comments
  types <- list()
  for (i in 1:nrow(desc$types)) {
    types[[desc$types[i,1]]] <- c(desc$types[i,2], desc$types[i,3])
  }
  attr(dat, 'types') <- types
  
  names(dat)[6:ncol(dat)] <- desc$types[,1]


  unlink(csvfile)
  dat
}

.get.xml.file <- function(url, dest, quiet) {
  status <- try(download.file(url, destfile=dest, method='internal', mode='wb', quiet=quiet),
      silent=TRUE)

  if (class(status) == 'try-error') {
    stop("Error in the download")
  }
}


#################################
#
# Get compound data
#
#################################


.eh <- function() {
  .itemNames <- c('IUPACName','CanonicalSmile','MolecularFormula','MolecularWeight', 'TotalFormalCharge',
                  'XLogP', 'HydrogenBondDonorCount', 'HydrogenBondAcceptorCount',
                  'HeavyAtomCount', 'TPSA')
  .types <- c('character','character','character', 'double', 'integer', 'double', 'integer', 'integer',
              'integer', 'double')

  tmpdata <- data.frame(t(rep(0,11)))
  validItem <- FALSE
  textval <- NA

  aRow <- c()
  inDocSum <- FALSE
  inId <- FALSE

  startElement <- function(name, attr) {
    if (name == 'DocSum') {
      aRow <<- c()
      inDocSum <<- TRUE
    }

    if (name == 'Id') inId <<- TRUE

    if (name == 'Item' && attr[['Name']] %in% .itemNames) {
      validItem <<- TRUE
      textval <<- NA
    } else {
      validItem <<- FALSE
    }
    
  }
  
  endElement <- function(name) {
    if (name == 'DocSum') {
      inDocSum <<- FALSE
      tmpdata <<- rbind(tmpdata, aRow)
    }
    if (name == 'Id') {
      aRow <<- c(aRow, textval)
      inId <<- FALSE
    }
    if (name == 'Item' && validItem) {
      aRow <<- c(aRow, textval)
      validItem <<- FALSE
    }
  }

  text <- function(val) {
    if (inId) {
      textval <<- val
    }else if (inDocSum && validItem) {
      textval <<- val
    }
  }

  endDocument <- function() {
    names(tmpdata) <<- c('CID', .itemNames)
    tmpdata <<- tmpdata[-1,]

    ## now we need perform some casting
    for (i in 1:length(.types)) {
      type <- .types[i]
      if (type == 'integer') tmpdata[,i+1] <<- as.integer(tmpdata[,i+1])
      else if (type == 'double') tmpdata[,i+1] <<- as.double(tmpdata[,i+1])
    }
  }

  startDocument <- function() {
  }
  
  list(startElement=startElement, endElement=endElement, text=text,
       endDocument=endDocument, startDocument=startDocument, data=function() {tmpdata})
}

get.cid <- function(cid, quiet=TRUE, from.file=FALSE) {

  datafile <- NA
  
  if (!from.file) {
    cidURL <- 'http://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi?tool=rpubchem&db=pccompound&id='
    url <- paste(cidURL, paste(cid,sep='',collapse=','), sep='', collapse='')
    datafile <- tempfile(pattern = 'cid')
    .get.xml.file(url, datafile, quiet)
  } else {
    datafile <- cid
  }

  eventhandlers <- .eh()
  xmlEventParse(datafile, ignoreBlanks=TRUE, useTagName=TRUE, handlers=eventhandlers)
  eventhandlers$data()
}

#################################################
#
# Get substance associations from compound data
#
#################################################
.csideh <- function() {
  
  tmpdata <- list()
  tmpcid <- NA
  textval <-  NA
  inSIDList <- FALSE
  inDocSum <- FALSE
  inId <- FALSE
  sidc <- 0

  aRow <- c()
  
  startElement <- function(name, attr) {
    if (name == 'DocSum') {
      aRow <<- c()
      inDocSum <<- TRUE
    }

    if (name == 'Id') inId <<- TRUE
    
    if (name == 'Item' && attr[['Name']] == 'SubstanceIDList') {
      inSIDList <<- TRUE
      textval <- NA
    }

    if (name == 'Item' && inSIDList && attr[['Name']] != 'SubstanceIDList') sidc <<- sidc+1
    
  }
  
  endElement <- function(name) {
    if (name == 'DocSum') {
      inDocSum <<- FALSE
      tmpdata[[tmpcid]] <<- aRow
    }
    if (name == 'Id') {
      tmpcid <<- textval
      inId <<- FALSE
    }
    if (name == 'Item' && inSIDList) {
      sidc <<- sidc - 1
      if (sidc == 0) aRow <<- c(aRow, textval)
      else if (sidc == -1) {
        inSIDList <<- FALSE
        sidc <<- 0
      }
    }
  }

  text <- function(val) {
    if (inDocSum) {
      if (inSIDList || inId) 
        textval <<- val
    }
  }

  list(startElement=startElement, endElement=endElement, text=text,
       data=function() {tmpdata})
}

get.sid.list <- function(cid, quiet=TRUE, from.file=FALSE) {
  
  datafile <- NA
  
  if (!from.file) {
    cidURL <- 'http://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi?tool=rpubchem&db=pccompound&id='
    url <- paste(cidURL, paste(cid,sep='',collapse=','), sep='', collapse='')
    datafile <- tempfile(pattern = 'cid')
    .get.xml.file(url, datafile, quiet)
  } else {
    datafile <- cid
  }

  handlers <- .csideh()
  xmlEventParse(datafile,  ignoreBlanks=TRUE, useTagName=TRUE, handlers=handlers)
  handlers$data()
  
}

#################################
#
# Get substance data
#
#################################
get.sid <- function(sid, quiet=TRUE, from.file=FALSE) {

  datafile <- NA
  
  if (!from.file) {
    sidURL <- 'http://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi?tool=rpubchem&db=pcsubstance&id='
    url <- paste(sidURL, paste(sid,sep='',collapse=','), sep='', collapse='')
    datafile <- tempfile(pattern = 'sid')
    .get.xml.file(url, datafile, quiet)
  } else {
    datafile <- sid
  }

  eventhandlers <- .eh()
  xmlEventParse(datafile, ignoreBlanks=TRUE, useTagName=TRUE, handlers=eventhandlers)
  dat <- eventhandlers$data()
  names(dat)[1] <- 'SID'
  dat
}

#####################################
#
# Contributed code
#
#####################################

.find.compound.count <- function (compounds, quiet = TRUE) {
  ## If list of Compounds, collapse into OR combined querystring
  query <- paste (compounds, collapse ="+OR+")

  if (!quiet) cat('Query: ', query, '\n')

  ## Create search URL and download result
  searchURL <- "http://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi?db=pccompound&tool=rpubchem&term="
  url <- URLencode(paste(searchURL, query, sep = "", collapse = ""))
  tmpdest <- "srch"
  status <- try(download.file(url, destfile = tmpdest, method = "internal",
                              mode = "wb", quiet = quiet), silent = TRUE)
  if (class(status) == "try-error") {
    stop("Couldn't perform search")
  }

  ## Parse XML and return vector of counts for each Term in Query Strings
  xml <- xmlTreeParse(tmpdest)
  root <- xmlRoot(xml)

  ##
  ## Results are scattered across two lists:
  ## 1) TranslationStack/TermSet for Hits
  ## 2) ErrorList for Misses
  ## 
  termlist <- sub ("([^[]*).*", "\\1", 
                   sapply(xmlElementsByTagName(root, "Term", recursive = TRUE), xmlValue),
                   perl=TRUE)
  hitlist <- sapply(xmlElementsByTagName(root, "Count", recursive = TRUE), xmlValue)
  counts <- sapply (compounds, function(x) {
    if (length(which(termlist==x))==1) {
      as.integer(hitlist[which(termlist==x)+1])
    } else {
      0
    }
  })

  unlink(tmpdest)
  counts
}
