########
# 
########
library(proj4)
library(rgdal)
library(raster)

fieldfolder <- "../../../Fielddata/"

fdat <- read.table(paste(fieldfolder, "ET_field_data.csv", sep=""), header=T, sep=",")

### Define grid "coordinate reference system" (CRS)
# e.g. project to Africa LAEA
fdat.laea <- as.data.frame(project(cbind(fdat$Lon, fdat$Lat), "+proj=laea +ellps=WGS84 +lon_0=20 +lat_0=5 +units=m +no_defs"))
colnames(fdat.laea) <- c("x","y")
fdat <- cbind(fdat, fdat.laea)

### Specify grid cell ID's (GID's) and center point coordinates
# Define pixel resolution (res.pixel, in m)
res.pixel <- 1000

# GID-definition
xgid <- ceiling(abs(fdat$x)/res.pixel)
ygid <- ceiling(abs(fdat$y)/res.pixel)
gidx <- ifelse(fdat$x<0, paste("W", xgid, sep=""), paste("E", xgid, sep=""))
gidy <- ifelse(fdat$y<0, paste("S", ygid, sep=""), paste("N", ygid, sep=""))
GID <- paste(gidx, gidy, sep="-")
fdat.gid <- cbind(fdat, GID)

# Gtif data
# get all the neighoring grid locations
locations_gid <- matrix(NA, dim(fdat.laea)[1], 18)

gtiffolder <- "../../../GEOdata/ET_1k_Gtif_CMA/"
# covariates interested   
grid.list <- list.files(gtiffolder, pattern = "\\.tif$")[list.files(gtiffolder, pattern = "\\.tif$")!= "pred_grid_1K.tif"]
grid.list.loc <- paste(gtiffolder, grid.list, sep="") 

# read in the prediction grids, and attach covariates in it
nm <-  grid.list.loc[1]
#raster fileinfo
tif.info <- GDALinfo(nm, silent=TRUE)
totalrows <- tif.info[1]
totalcols <- tif.info[2]
bandsnum <- tif.info[3]
origin.x <- tif.info[4]
res.x <- tif.info[6]
res.y <- tif.info[7]
if(attr(tif.info, "ysign")==-1){
	#origin of data array should be the left upper corner
	origin.y <- tif.info[5] + totalrows*res.y
}else{
	origin.y <- tif.info[5]	
}
	
pixeln.x <- ceiling((fdat.laea$x-origin.x)/res.x)-1
pixeln.y <- ceiling((origin.y-fdat.laea$y)/res.y)-1
neighbor.x <- c(-1, 0, 1, -1,0,1, -1, 0, 1)
neighbor.y <- c(-1, -1, -1, 0, 0, 0, 1, 1, 1)
locations_gid  <-  matrix(NA, dim(fdat.laea)[1], 18)

for(i in 1:9){
	locations_gid[, (2*i-1)] <- (pixeln.x+neighbor.x[i])*res.x + origin.x + res.x/2
	locations_gid[, (2*i)] <- origin.y - ((pixeln.y+neighbor.y[i])*res.y + res.y/2)
}

colnames(locations_gid) <- c("2nb1x","2nb1y" ,"1nb1x", "1nb1y", "2nb2x", "2nb2y", "1nb2x", "1nb2y","locx", "locy", "1nb3x", "1nb3y", "2nb3x", "2nb3y", "1nb4x", "1nb4y", "2nb4x", "2nb4y")

fdat.gid <- cbind(fdat, GID)

for(j in 1:9){
	temp <- cbind(fdat.gid[,1], x=locations_gid[, (2*j-1)], y = locations_gid[, (2*j)])
	temp <- as.data.frame(temp)
	coordinates(temp) = ~ x+y
	for (i in 1:length(grid.list)) {
		print(paste("extracting", grid.list.loc[i]))
		rmap_bndry_new <- raster(grid.list.loc[i]) # raster is producing small file size in the memory as compared to readGDAL
		temp@data[paste(strsplit(grid.list[i], split=".tif")[[1]],substring(colnames(locations_gid)[(2*j-1)],1, 4), sep="_")] <- extract (
		  	x = rmap_bndry_new, # evi data 
		  	y = temp, # original data
		  	method = "simple"
		 )
	}
	fdat.gid <- cbind(fdat.gid, temp@data[,-1])
}

# predict CMA
ratio_data <- cbind(fdat.gid$VSSE/4, fdat.gid[, (dim(fdat)[2]+2):(dim(fdat.gid)[2])])
ratio_data <- na.omit(ratio_data)
#cma_data <- aggregate(cma_data, by=list(fdat.gid$GID), rowMeans)
# library(randomForest)

# cma.rf <- randomForest((CMA) ~ ., data=cma_data, importance=TRUE, proximity=TRUE)
# tuneRF.cma <- tuneRF(cma_data[,-1], as.factor(cma_data$CMA))

# rfcma.predict <- predict(cma.rf, rmap_bndry[, -c(1, 2, 3)])

# aggregate : does not work well, hard to estimate medium category due to lack of data
# cma_data <- cbind(CMA=(fdat.gid$CMA), fdat.gid[, 33:167])
# cma_data_aggregate <- unique(fdat.gid$GID)
# for(i in 1:dim(cma_data)[2]){
	# cma_data_aggregate <- cbind(cma_data_aggregate, aggregate(cma_data[,i], by=list(fdat.gid$GID), mean)[,2])
# }
# cma_data_aggregate <- as.data.frame(cma_data_aggregate)
# names(cma_data_aggregate) <- c("GID", names(cma_data))

# cma_data_aggregate$CMA <- ifelse(cma_data_aggregate$CMA==0.5, "medium", ifelse(cma_data_aggregate$CMA>0.5, "high", "low"))
# cma.rf <- randomForest((CMA) ~ ., data=cma_data_aggregate, importance=TRUE, proximity=TRUE)

# BART prediction
library(BayesTree)

x <- ratio_data[,-1]
y <- ratio_data[,1]

bart.est <- bart(x, y, ndpost=500, nskip=2000, keepevery=10)

save.image("bart.est.RData")


predict.bart <- bart.est$yhat.test
for(i in 1:dim(predict.bart)[1]){
	for(j in 1:dim(predict.bart)[2]){
		predict.bart[i, j] <- ifelse(predict.bart[i, j]>1, 1, ifelse(predict.bart[i, j]<0, 0, predict.bart[i, j]))
	}
}

predict.bart.mean <-  apply(predict.bart,2,mean)
predict.bart.sd <- apply(predict.bart, 2, sd)

predict_grid_1k <- SpatialPointsDataFrame(
  coords = predict_grid_1k_coords,
  data = data.frame(
 predict.mean =predict.mean,
 predict.se = predict.se)
)

gridded(predict_grid_1k) <- TRUE

writeGDAL(
  	dataset = predict_grid_1k["predict.mean"],
  	fname ="erosionpredict.tif",
  	drivername = "GTiff",
  	type = "Float32",
  	Overwrite<- TRUE)
  	

  	  	  	
writeGDAL(
  	dataset = predict_grid_1k["predict.se"],
  	fname ="erosionpredict_se.tif",
  	drivername = "GTiff",
  	type = "Float32",
  	Overwrite<- TRUE)
  	
 

