#' @title Buffer clound masks
#' @description Internal function (used by [2s_mask]) which smooths
#'  and buffers a 0-1 mask image in order to reduce the roughness of the mask
#'  obtained from SCL classification (which is done pixel by pixel).
#'  See details.
#' @param inmask The path of the input 0-1 mask (where 0 represents the area
#'  to be masked, 1 the cleen surface).
#' @param binpaths list of paths of binaries.
#' @param tmpdir (optional) Path where intermediate files (VRT) will be created.
#'  Default is a temporary directory.
#' @param radius (optional) Numerical (positive): the size (in the unit of
#'  `inmask`, typically metres) to be used as radius for the smoothing
#'  (the higher it is, the more smooth the output mask will result).
#' @param buffer (optional) Numerical (positive or negative): the size of the 
#'  buffer (in the unit of `inmask`, typically metres) to be applied to the 
#'  masked area after smoothing it (positive to enlarge, negative to reduce).
#' @return The path of the smoothed mask.
#' @export
#' @importFrom rgdal GDALinfo
#' @importFrom methods is
#' @author Luigi Ranghetti, phD (2018) \email{ranghetti.l@@irea.cnr.it}
#' @note License: GPL 3.0

smooth_mask <- function(inmask, binpaths, tmpdir, radius, buffer) {

  # if inmask is a raster use the path (it should not happen)
  inmask_path0 <- if (is(inmask, "character")) {
    inmask
  } else {
    inmask@file@name
  }
  
  # convert radius and buffer from metres to number of pixels
  # (as required by gdal_fillnodata)
  inmask_res <- mean(suppressWarnings(GDALinfo(inmask_path0)[c("res.x","res.y")]))
  radius_npx <- radius / inmask_res
  buffer_npx <- buffer / inmask_res
  


  # 1. set 1 (clouds) to NA
  inmask_path1 <- file.path(tmpdir,basename(tempfile(pattern = "mask_", fileext = ".tif")))
  system(
    paste0(binpaths$gdal_translate," -of GTiff -co COMPRESS=LZW -a_nodata 1 ",inmask_path0," ",inmask_path1),
    intern = Sys.info()["sysname"] == "Windows"
  )
  
  # 2. firs positive buffer (1/2 radius)
  inmask_path2 <- gsub("\\.tif$","_2.tif",inmask_path1)
  system(
    paste0("gdal_fillnodata.py"," -md ",radius_npx*3/4," -si 0 -of GTiff -co COMPRESS=LZW ",inmask_path1," ",inmask_path2),
    intern = Sys.info()["sysname"] == "Windows"
  )
  
  # 3. invert the image (0 to na)
  inmask_path3 <- gsub("\\.tif$","_3.tif",inmask_path1)
  system(
    paste0(binpaths$gdal_translate," -of GTiff -co COMPRESS=LZW -a_nodata 0 ",inmask_path2," ",inmask_path3),
    intern = Sys.info()["sysname"] == "Windows"
  )

  # 2. second negative buffer (3/4 radius + 5/4 radius)
  inmask_path4 <- gsub("\\.tif$","_4.tif",inmask_path1)
  system(
    paste0("gdal_fillnodata.py"," -md ",radius_npx*2," -si 0 -of GTiff -co COMPRESS=LZW ",inmask_path3," ",inmask_path4),
    intern = Sys.info()["sysname"] == "Windows"
  )
  
  # 5. invert the image (1 to na)
  inmask_path5 <- gsub("\\.tif$","_5.tif",inmask_path1)
  system(
    paste0(binpaths$gdal_translate," -of GTiff -co COMPRESS=LZW -a_nodata 1 ",inmask_path4," ",inmask_path5),
    intern = Sys.info()["sysname"] == "Windows"
  )
  
  # 6. third positive buffer (5/4 radius to complete smooth, buffer to buffer if < 0, to 3/2 buffer if >0)
  inmask_path6 <- gsub("\\.tif$","_6.tif",inmask_path1)
  system(
    paste0("gdal_fillnodata.py"," -md ",radius_npx*5/4+ifelse(buffer_npx>0,buffer_npx*3/2,buffer_npx)," -si 0 -of GTiff -co COMPRESS=LZW ",inmask_path5," ",inmask_path6),
    intern = Sys.info()["sysname"] == "Windows"
  )
  
  # 7-8 if buffer_npx > 0 
  if (buffer_npx > 0) {
    
    # 7. invert the image (1 to na)
    inmask_path7 <- gsub("\\.tif$","_7.tif",inmask_path1)
    system(
      paste0(binpaths$gdal_translate," -of GTiff -co COMPRESS=LZW -a_nodata 0 ",inmask_path6," ",inmask_path7),
      intern = Sys.info()["sysname"] == "Windows"
    )
    
    # 8. fourth negative buffer (1/2)
    inmask_path8 <- gsub("\\.tif$","_8.tif",inmask_path1)
    system(
      paste0("gdal_fillnodata.py"," -md ",buffer_npx/2," -si 0 -of GTiff -co COMPRESS=LZW ",inmask_path7," ",inmask_path8),
      intern = Sys.info()["sysname"] == "Windows"
    )
    
  }
  
  # 9. remove nodata labels
  inmask_path9 <- gsub("\\.tif$","_9.tif",inmask_path1)
  system(
    paste0(binpaths$gdal_translate," -of GTiff -co COMPRESS=LZW -a_nodata none ",ifelse(buffer_npx>0,inmask_path8,inmask_path6)," ",inmask_path9),
    intern = Sys.info()["sysname"] == "Windows"
  )
  
  inmask_path9

}