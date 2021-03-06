#' @title Download S2 products.
#' @description The function downloads S2 products.
#'  Input filenames must be elements obtained with
#'  [s2_list] function
#'  (each element must be a URL, and the name the product name).
#' @param s2_prodlist Named character: list of the products to be downloaded,
#'  in the format `safelist` (see [safelist-class]).
#'  Alternatively, it can be the path of a JSON file exported by [s2_order].
#' @param downloader Executable to use to download products
#'  (default: "builtin"). Alternatives are "builtin" or "aria2"
#'  (this requires aria2c to be installed).
#' @param apihub Path of the "apihub.txt" file containing credentials
#'  of SciHub account.
#'  If NA (default), the default location inside the package will be used.
#' @param tile Deprecated argument
#' @param outdir (optional) Full name of the existing output directory
#'  where the files should be created (default: current directory).
#' @param order_lta Logical: if TRUE (default), products which are not available
#'  for direct download are ordered from the Long Term Archive;
#'  if FALSE, they are simply skipped.
#' @param overwrite Logical value: should existing output archives be
#'  overwritten? (default: FALSE)
#' @return NULL (the function is called for its side effects)
#'
#' @author Luigi Ranghetti, phD (2019) \email{luigi@@ranghetti.info}
#' @author Lorenzo Busetto, phD (2019) \email{lbusett@@gmail.com}
#' @note License: GPL 3.0
#' @importFrom httr GET RETRY authenticate progress write_disk
#' @importFrom foreach foreach "%do%"
#' @export
#'
#' @examples
#' \dontrun{
#' single_s2 <- paste0("https://scihub.copernicus.eu/apihub/odata/v1/",
#'   "Products(\'c7142722-42bf-4f93-b8c5-59fd1792c430\')/$value")
#' names(single_s2) <- "S2A_MSIL1C_20170613T101031_N0205_R022_T32TQQ_20170613T101608.SAFE"
#' # (this is equivalent to:
#' # single_s2 <- example_s2_list[1]
#' # where example_s2_list is the output of the example of the
#' # s2_list() function)
#'
#' # Download the whole product
#' s2_download(single_s2, outdir=tempdir())
#'
#' #' # Download the whole product - using aria2
#' s2_download(single_s2, outdir=tempdir(), downloader = "aria2")
#'
#' # Download more products, ordering the ones stored in the Long Term Archive
#' pos <- sf::st_sfc(sf::st_point(c(-57.8815,-51.6954)), crs = 4326)
#' time_window <- as.Date(c("2018-02-21", "2018-03-20"))
#' list_safe <- s2_list(spatial_extent = pos, time_interval = time_window)
#' s2_download(list_safe, outdir=tempdir())
#' }

s2_download <- function(
  s2_prodlist = NULL,
  downloader = "builtin",
  apihub = NA,
  tile = NULL,
  outdir = ".",
  order_lta = TRUE,
  overwrite = FALSE
) {
  
  # warn for deprecated arguments
  if (!missing("tile")) {
    warning("argument 'tile' is deprecated and will not be used")
  }
  
  .s2_download(
    s2_prodlist = s2_prodlist,
    downloader = downloader,
    apihub = apihub,
    outdir = outdir,
    order_lta = order_lta,
    overwrite = overwrite,
    .s2_availability = NULL
  )
  
}

# internal function, used internally in order not to repeat the check
# for online availability
.s2_download <- function(
  s2_prodlist = NULL,
  downloader = "builtin",
  apihub = NA,
  outdir = ".",
  order_lta = TRUE,
  overwrite = FALSE,
  .s2_availability = NULL
) {
  
  # convert input NA arguments in NULL
  for (a in c("s2_prodlist", "apihub")) {
    if (suppressWarnings(all(is.na(get(a))))) {
      assign(a,NULL)
    }
  }
  
  # exit if empty
  if (length(nn(s2_prodlist)) == 0) {
    return(invisible(NULL))
  }
  
  # check input format
  s2_prodlist <- as(s2_prodlist, "safelist")
  # TODO add input checks
  
  # read credentials
  creds <- read_scihub_login(apihub)
  
  # check downloader
  if (!downloader %in% c("builtin", "aria2", "aria2c")) {
    print_message(
      type = "warning",
      "Downloader \"",downloader,"\" not recognised ",
      "(builtin will be used)."
    )
    downloader <- "builtin"
  }
  
  # Split products to be downloaded from products to be ordered
  s2_availability <- if (is.null(.s2_availability)) {
    print_message(
      type = "message",
      date = TRUE,
      "Check if products are available for download..."
    )
    safe_is_online(s2_prodlist)
  } else {
    .s2_availability
  }

  
  # Order products stored from the Long Term Archive
  if (order_lta == TRUE) {
    ordered_products <- .s2_order(s2_prodlist, .s2_availability = s2_availability)
  }

  
  ## Download products available for download
  
  for (i in which(s2_availability)) {
    
    link <- s2_prodlist[i]
    zip_path <- file.path(outdir, paste0(names(s2_prodlist[i]),".zip"))
    safe_path <- gsub("\\.zip$", "", zip_path)
    
    if (any(overwrite == TRUE, !file.exists(safe_path))) {
      
      print_message(
        type = "message",
        date = TRUE,
        "Downloading Sentinel-2 image ", which(i == which(s2_availability)),
        " of ",sum(s2_availability)," (",basename(safe_path),")..."
      )
      
      if (downloader %in% c("builtin", "wget")) { # wget left for compatibility
        
        download <- httr::RETRY(
          verb = "GET",
          url = as.character(link),
          config = httr::authenticate(creds[1], creds[2]),
          times = 10,
          httr::progress(),
          httr::write_disk(zip_path, overwrite = TRUE)
        )
        
      } else if (grepl("^aria2c?$", downloader)) {
        
        binpaths <- load_binpaths("aria2")
        if (Sys.info()["sysname"] != "Windows") {
          link <- gsub("/\\$value", "/\\\\$value", link)
        }
        aria_string <- paste0(
          binpaths$aria2c, " -x 2 --check-certificate=false -d ",
          dirname(zip_path),
          " -o ", basename(zip_path),
          " ", "\"", as.character(link), "\"",
          " --allow-overwrite --file-allocation=none --retry-wait=2",
          " --http-user=", "\"", creds[1], "\"",
          " --http-passwd=", "\"", creds[2], "\"",
          " --max-tries=10"
        )
        download <- try({
          system(aria_string, intern = Sys.info()["sysname"] == "Windows")
        })
        
      }

      # check if the user asked to download a LTA product
      download_is_lta <- if (inherits(download, "response")) {
        download$status_code == 202
      } else if (inherits(download, "integer")) {
        download == 22
      } else FALSE
      if (download_is_lta) {
        # TODO
      }
      
      if (inherits(download, "try-error")) {
        suppressWarnings(file.remove(zip_path))
        suppressWarnings(file.remove(paste0(zip_path,".aria2")))
        print_message(
          type = "error",
          "Download of file", link, "failed more than 10 times. ",
          "Internet connection or SciHub may be down."
        )
      } else {
        # check md5
        check_md5 <- tryCatch({
          sel_md5 <- httr::GET(
            url = gsub("\\$value$", "Checksum/Value/$value", as.character(link)),
            config = httr::authenticate(creds[1], creds[2]),
            httr::write_disk(md5file <- tempfile(), overwrite = TRUE)
          )
          md5 <- toupper(readLines(md5file, warn = FALSE)) == toupper(tools::md5sum(zip_path))
          file.remove(md5file)
          md5
        }, error = function(e) {logical(0)})
        if (length(check_md5) == 0) {
          print_message(
            type = "warning",
            "File ", names(link), " cannot be checked. ",
            "Please verify if the download was successful."
          )
        } else if (!check_md5) {
          file.remove(zip_path)
          print_message(
            type = "error",
            "Download of file ", names(link), " was incomplete (Md5sum check failed). ",
            "Please retry to launch the download."
          )
        }
        # remove existing SAFE
        if (dir.exists(safe_path)) {
          unlink(safe_path, recursive = TRUE)
        }
        # unzip
        unzip(zip_path, exdir = dirname(zip_path))
        file.remove(zip_path)
      }
      
    } else {
      
      print_message(
        type = "message",
        date = TRUE,
        "Skipping Sentinel-2 image ", i," of ",which(i == which(s2_availability)),
        " of ",sum(s2_availability),") ",
        "since the corresponding folder already exists."
      )
      
    }
    
  }
  
  return(invisible(NULL))
  
}
