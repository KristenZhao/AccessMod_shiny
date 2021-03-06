#      ___                                  __  ___            __   ______
#     /   |  _____ _____ ___   _____ _____ /  |/  /____   ____/ /  / ____/
#    / /| | / ___// ___// _ \ / ___// ___// /|_/ // __ \ / __  /  /___ \
#   / ___ |/ /__ / /__ /  __/(__  )(__  )/ /  / // /_/ // /_/ /  ____/ /
#  /_/  |_|\___/ \___/ \___//____//____//_/  /_/ \____/ \__,_/  /_____/

#'amReferralTable
#'@export
amAnalysisReferral<-function(
  session=shiny:::getDefaultReactiveDomain(),
  inputSpeed,
  inputFriction,
  inputHf,
  inputHfTo,
  inputTableHf,
  inputTableHfTo,
  idField,
  idFieldTo,
  labelField,
  labelFieldTo,
  typeAnalysis,
  limitClosest,
  resol,
  dbCon,
  unitCost=c('s','m','h'),
  unitDist=c('m','km'),
  outReferral,
  outNearestDist,
  outNearestTime,
  maxCost,
  pBarTitle="Referral analysis"
  ){

  amTimer("start")

  #
  # set increment for the progress bar.
  #
  incN <- 0
  incTot <- nrow(inputTableHf)
  inc <- 100/nrow(incTot)

  #
  # set output table label
  #
  hIdField <- paste0('from','__',amSubPunct(idField)) # amSubPunt to avoid unwanted char (accent, ponctuation..)
  hLabelField <- paste0('from','__',amSubPunct(labelField))
  hIdFieldTo <- paste0('to','__',amSubPunct(idFieldTo))
  hLabelFieldTo <- paste0('to','__',amSubPunct(labelFieldTo))
  hIdFieldNearest <-  paste0('nearest','__',amSubPunct(idFieldTo))
  hLabelFieldNearest <-  paste0('nearest','__',amSubPunct(labelFieldTo))
  hDistUnit <-paste0('distance','_',unitDist)
  hTimeUnit <- paste0('time','_',unitCost)

  #
  # set local identifier columns
  #
  idCol <- config$vectorKey
  idColTo <- paste0(config$vectorKey,"_to")

  #
  # Get ids list for origin and destination
  #

  #listFrom <- inputTableHf[,idField]
  #listTo <- inputTableHfTo[,idFieldTo]
  listFrom <- inputTableHf[,idCol]
  listTo <- inputTableHfTo[,idCol]

  #
  # Set output table structure
  #
  tblRefTemplate <- data.frame(
    f=character(0),
    l=character(0),
    ft=character(0),
    lt=character(0),
    dk=numeric(0),
    tm=numeric(0)
    )
  names(tblRefTemplate) <-c(
    hIdField,
    hLabelField,
    hIdFieldTo,
    hLabelFieldTo,
    hDistUnit,
    hTimeUnit
    )

  tblRef <- tblRefTemplate
  tblRefOut <- tblRefTemplate
  tblRefNearestTime <- tblRefTemplate
  tblRefNearestDist <- tblRefTemplate


  #
  # Send progress state. Here, first message
  #
  pbc(
    visible = TRUE,
    timeOut = 2,
    percent = 1,
    title   = pBarTitle,
    text    = sprintf("Compute referral for %s facilities, please be patient. Click on stop button to interrupt."
      , incTot
      )
    )

  # cost and dist from one to all selected in table 'to'
  for(i in listFrom){  

    incN <- incN+1

    pBarPercent <- (incN-1)/incTot * 100 
    #
    # Don't ccompute distance to self
    #
    listToSub <- listTo[!listTo == i]
    #
    # Init local var
    #
    refTableIter <- tblRefTemplate
    refDist <- data.frame()
    refTime <- data.frame()
    refDistTime <- data.frame()
    hasNoDest <- TRUE
    closestHf <- 0

    pbc(
      visible = TRUE,
      percent = pBarPercent,
      title   = pBarTitle,
      text    = sprintf("%1$s/%2$s (%3$s) Extract vector data."
        , incN
        , incTot
        , amTimer()
        )
      )

    #
    # subset hf from 
    #
    qSqlFrom <- sprintf("%s == '%s'",
      idCol,
      i
      )
    execGRASS("v.extract",
      flags = c('overwrite'),
      input = inputHf,
      where = qSqlFrom,
      output='tmp__ref_from'
      )

    #
    # subset hf to 
    #
    qSqlTo <- sprintf(" %1$s IN ( %2$s )",
      idCol,
      paste0(listToSub,collapse=',')
      )

    execGRASS("v.extract",
      flags = c('overwrite'),
      input = inputHfTo,
      where = qSqlTo,
      output = 'tmp__ref_to'
      )

    #
    # create cumulative cost map for each hf : iso or aniso
    # 
    pbc(
      visible = TRUE,
      percent = pBarPercent,
      title   = pBarTitle,
      text    = sprintf("%1$s/%2$s (%3$s) Compute travel time."
        , incN
        , incTot
        , amTimer()
        )
      )
    switch(typeAnalysis,
      'anisotropic' = amAnisotropicTravelTime(
        inputSpeed = inputSpeed,
        inputHf = 'tmp__ref_from',
        inputStop = 'tmp__ref_to',
        outputCumulative = 'tmp__cost', 
        outputDir = 'tmp__ref_dir',
        returnPath = FALSE,
        maxCost = maxCost
        ),
      'isotropic' = amIsotropicTravelTime(
        inputFriction = inputFriction,
        inputHf = 'tmp__ref_from',
        inputStop = 'tmp__ref_to',
        outputCumulative = 'tmp__cost',
        outputDir = 'tmp__ref_dir',
        maxCost = maxCost
        )
      )

    #
    # extract time cost V1 = hf id dest; V2 = time to reach hf
    #
    pbc(
      visible = TRUE,
      percent = pBarPercent,
      title   = pBarTitle,
      text    = sprintf("%1$s/%2$s (%3$s) Extract travel time."
        , incN
        , incTot
        , amTimer()
        )
      )

    #
    # extact cost for each destination point
    #
    refTimeText = execGRASS(
      'v.what.rast',
      map='tmp__ref_to',
      raster='tmp__cost',
      flags='p',
      intern=T
      )
    refTime <- read.table(
      text = refTimeText,
      sep ='|',
      stringsAsFactor = F,
      na.strings = "*",
      colClasses = c(typeof(i),"numeric")
      )
     

    # rename grass output
    names(refTime) <- c(idColTo,hTimeUnit)

    # set "from" value
    refTime[[idCol]] <- i

    #
    # Convert units
    # 
    if( !unitCost =='m' ){
      div<-switch(unitCost,
        's'=1/60,
        'm'=1,
        'h'=60,
        'd'=24
        )
      refTime[hTimeUnit]<-refTime[hTimeUnit]/div
    }

    #
    # Check if all destination are unreachable
    #
    hasNoDest <- isTRUE(all(is.na(refTime[hTimeUnit])))

    #
    # extract distance
    #
    if( hasNoDest ){

      #
      # Use refTime as template for distances
      #
      refDist <- refTime
      names(refDist)[names(refDist) == hTimeUnit] <- hDistUnit

    }else{

      #
      # subset closest destination point if needed
      #
      if( limitClosest ){

        closestHf <- refTime[which.min(refTime[,hTimeUnit]),idColTo]

        qSqlTo <- sprintf(" %1$s = %2$s "
          , idCol
          , closestHf
          )
        # extract to temp vector
        execGRASS(
          "v.extract",
          flags = c('overwrite'),
          input = inputHfTo,
          where = qSqlTo,
          output = 'tmp__ref_to'
          )
      }


      pbc(
        visible = TRUE,
        percent = pBarPercent,
        title   = pBarTitle,
        text    = sprintf("%1$s/%2$s (%3$s) Compute least cost path."
          , incN
          , incTot
          , amTimer()
          )
        )


      # least cost path using direction and cost
      execGRASS('r.drain',
        input = 'tmp__cost',
        direction = 'tmp__ref_dir',
        output =  'tmp__drain',
        drain = 'tmp__drain',
        flags = c('overwrite','c','d'),
        start_points = 'tmp__ref_to'
        )

      # create new layer with start point as node
      pbc(
        visible = TRUE,
        percent = pBarPercent,
        title   = pBarTitle,
        text    = sprintf("%1$s/%2$s (%3$s) Build vector network"
          , incN
          , incTot
          , amTimer()
          )
        )

      #
      # Connect the starting facilities to the drain path
      #
      execGRASS('v.net',
        input = 'tmp__drain',
        points = 'tmp__ref_from',
        output = 'tmp__net_from',
        node_layer = '2',
        operation = 'connect',
        threshold = resol-1,
        flags = 'overwrite'
        )

      #
      # Connect the destination facility to the network
      #
      execGRASS('v.net',
        input = 'tmp__net_from',
        points = 'tmp__ref_to',
        output = 'tmp__net_all',
        node_layer = '3',
        operation = 'connect',
        threshold = resol-1,
        flags = 'overwrite'
        )

      pbc(
        visible = TRUE,
        percent = pBarPercent,
        title   = pBarTitle,
        text    = sprintf("%1$s/%2$s (%3$s) Calculate distances."
          , incN
          , incTot
          , amTimer()
          )
        )

      #
      # Calculate distance on the net
      #
      execGRASS('v.net.distance',
        input='tmp__net_all',
        output='tmp__net_dist',
        from_layer='3', # calc distance from all node in 3 to layer 2 (start point)     
        to_layer='2',
        intern=T,
        flags='overwrite'
        )

      #
      # Read attribute table of distance network.
      #
      pbc(
        visible = TRUE,
        percent = pBarPercent,
        title   = pBarTitle,
        text    = sprintf("%1$s/%2$s (%3$s) Extract result and aggregate."
          , incN
          , incTot
          , amTimer()
          )
        )

      #
      # Read and rename calculated distances
      #
      refDist <- dbReadTable(dbCon,'tmp__net_dist')
      names(refDist)<-c(idColTo,idCol,hDistUnit)
      #
      # Convert distances
      #
      if(!unitDist=='m'){
        div<-switch(unitDist,
          'km'=1000
          )
        refDist[,hDistUnit]<-refDist[,hDistUnit]/div
      }

    }

    #
    # Merge dist and time
    #
    refDistTime <- merge(
      refDist
      , refTime
      , by=c( idCol, idColTo )
      , all.y=T
      )

    # 
    # Append to existing
    #
    if(nrow(tblRef) == 0){
      tblRef <- refDistTime
    }else{
      tblRef <- rbind(tblRef,refDistTime)
    }

    # remove tmp map
    rmRastIfExists('tmp__*')
    rmVectIfExists('tmp__*')

  } # end of loop

  #
  # cleaning temp files
  #
  rmVectIfExists('tmp_*')

  pbc(
    visible = TRUE,
    percent = 99,
    timeOut = 5,
    title   = pBarTitle,
    text    = sprintf("Referral analysis done in %s. Creation of output tables."
      , amTimer()
      )
    )

  #
  # Set final tables
  #
  tblFrom <- inputTableHf[,c(config$vectorKey,idField,labelField)]
  tblTo <- inputTableHfTo[,c(config$vectorKey,idFieldTo,labelFieldTo)]

  names(tblFrom) <- c(config$vectorKey,hIdField,hLabelField)
  names(tblTo) <- c(config$vectorKey,hIdFieldTo,hLabelFieldTo)

  tblOut <-  merge(tblRef, tblTo
    , by.x=idColTo
    , by.y=idCol)
  
  tblOut <- merge(tblOut,tblFrom
    , by=idCol)

  tblOut <- tblOut[,c(1,2,7,8,5,6,3,4)]
  #
  # Subset Nearest by time
  #
  tblRefNearestTime <- tblOut[0,]
  tblRefNearestDist <- tblOut[0,]

  for(l in listFrom ){
    subTbl <- tblOut[tblOut[,idCol] == l,]
    rowMinTime <- subTbl[which.min(subTbl[[hTimeUnit]]),]
    rowMinDist <- subTbl[which.min(subTbl[[hDistUnit]]),]
    if( nrow(rowMinTime) == 0 ) {
      rowMinTime <- subTbl[1,]
      rowMinTime[,c(5,6,7,8)] <- NA
    }

    if(nrow(rowMinDist) == 0) {
      rowMinDist <- subTbl[1,]
      rowMinDist[,c(5,6,7,8)] <- NA
    }

    tblRefNearestDist <- rbind(tblRefNearestDist,rowMinDist)
    tblRefNearestTime <- rbind(tblRefNearestTime,rowMinTime)
  }

  #
  # clean tables id
  #
  tblRefNearestDist[,c(1,2)] <- NULL
  tblRefNearestTime[,c(1,2)] <- NULL
  tblOut[,c(1,2)] <- NULL

  #
  # Write tables
  #
  if(!limitClosest) dbWriteTable(dbCon,outNearestDist,tblRefNearestDist,overwrite=T,row.names=F)
  dbWriteTable(dbCon,outReferral,tblOut,overwrite=T,row.names=F)
  dbWriteTable(dbCon,outNearestTime,tblRefNearestTime,overwrite=T,row.names=F)

  # Return meta data
  meta<-list(
    'Function'='amReferralTable',
    'AccessMod revision'=amGetAppVersionLocal(),
    'Date'=amSysTime(),
    'Iterations'=nrow(inputTableHf),
    'Arguments'=list(
      'input'=list(
        'map'=list(
          'cost'=list(
            'speed'=inputSpeed,
            'friction'=inputFriction
            ),
          'facilities'=list(
            'from'=inputHf,
            'to'=inputHfTo
            )
          ),
        'table'=list(
          'id'=list(
            'from'=inputTableHf[[config$vectorKey]],
            'to'=inputTableHfTo[[config$vectorKey]]
            ),
          'names'=list(
            'from'=names(inputTableHf),
            'to'=names(inputTableHfTo)
            )
          )
        ),
      'analysis'=typeAnalysis,
      'unit'=list(
        'distance'=unitDist,
        'cost'=unitCost
        ),
      'resol'=resol
      ),
    'Output'=list(
      outReferral,
      outNearestDist,
      outNearestTime
      ) 
    )

  pbc(
    percent = 100,
    visible = FALSE
    )

}


