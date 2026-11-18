// swift-tools-version: 5.9
import PackageDescription
let package = Package(name:"MoyuCore", platforms:[.macOS(.v13),.iOS(.v16)],
products:[.library(name:"MoyuCore",targets:["MoyuCore"])],
dependencies:[.package(url:"https://github.com/weichsel/ZIPFoundation.git",exact:"0.9.19")],
targets:[.target(name:"MoyuCore",dependencies:[.product(name:"ZIPFoundation",package:"ZIPFoundation")],path:"Sources/Domain"),
.testTarget(name:"MoyuCoreTests",dependencies:["MoyuCore"],path:"Tests")])
