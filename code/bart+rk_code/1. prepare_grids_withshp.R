# preparing prediction grids with covariates attached

# attach packages
suppressPackageStartupMessages(require(rgdal, quietly=TRUE, warn.conflicts=FALSE)) # to import and export spatial data
suppressPackageStartupMessages(require(raster, quietly =TRUE, warn.conflicts=FALSE)) # for handling raster maps
suppressPackageStartupMessages(require(maptools, quietly =TRUE, warn.conflicts=FALSE)) # for handling raster maps

GID <- function(location){
    res.pixel <- 1000
    xgid <- floor(location[,1]/res.pixel)
    ygid <- floor(location[,2]/res.pixel)
    gidx <- ifelse(location[,1]<0, paste("W", xgid, sep=""), paste("E", xgid, sep=""))
    gidy <- ifelse(location[,2]<0, paste("S", ygid, sep=""), paste("N", ygid, sep=""))
    GID <- paste(gidx, gidy, sep="-")
    return(list(xgid=xgid, ygid=ygid, GID=GID))
}


# folder contraining all the covariates tif files
gtiffolder <- "../../../GEOdata/ET_1k_Gtif"
# covariates interested   
grid.list <- c("BLUE.tif", "BSAn.tif", "BSAs.tif", "BSAv.tif", "CTI.tif", "ELEV.tif", "EVI.tif", "FPAR.tif", "LAI.tif", "LSTd.tif", "LSTn.tif", "MAP.tif", "MAT.tif", "MIR.tif", "NDVI.tif", "NIR.tif", "RED.tif", "RELIEF.tif", "WSAn.tif", "WSAs.tif", "WSAv.tif")
 
# read in the prediction grids, and attach covariates in it
# only keep the locations which is not cliped

shapefile.one <- readShapePoly("tigray/Tigray_Reg_laea.shp")
wa.combined <- slot(shapefile.one, "polygons")
slot(wa.combined[[1]], "ID") <- "tigray"
wapolygons.combined <- SpatialPolygons(wa.combined)

predict_grid_1k_tif <- readGDAL(paste(gtiffolder, "/", "pred_grid_1K.tif", sep=""), silent=TRUE)
inside <- over(predict_grid_1k_tif, wapolygons.combined)

predict_grid_1k <- SpatialGridDataFrame(predict_grid_1k_tif, data=data.frame(list(ins=inside)))
predict_grid_1k <-  as(predict_grid_1k, "SpatialPixelsDataFrame")

predict_grid_1k_coords <- predict_grid_1k@coords


# use 'raster' to read a geotif from disk
for(i in 1:length(grid.list)){
	cat(paste("extracting", grid.list[i], "\n"))
	rmap_bndry_new <- raster(paste(gtiffolder, "/", grid.list[i], sep="")) # raster is producing small file size in the memory as compared to readGDAL
	predict_grid_1k@data[strsplit(grid.list[i], split=".tif")[[1]]] <- extract (
  	x = rmap_bndry_new, # covariates data 
  	y = predict_grid_1k, # original data
  	method = "simple"
	)
}

predict_grid_1k_values <- predict_grid_1k@data[, -1]
predict_grid_1k_values.narm <- predict_grid_1k_values[!is.na(rowMeans(predict_grid_1k_values)), ]
predict_grid_1k_values.narm <- as.matrix(predict_grid_1k_values.narm)
predict_grid_1k_coords <- predict_grid_1k_coords[!is.na(rowMeans(predict_grid_1k_values)), ]

predict_grid_1k_GID <- GID(predict_grid_1k_coords)
predict_grid_1k_values_withGID  <- data.frame(GID = predict_grid_1k_GID[[3]], predict_grid_1k_values.narm)

