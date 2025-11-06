BUILD_DIR := "./build"
DIST_DIR_PROV := "lit-os-prov"
DIST_DIR_NODE := "lit-os-node"

all: clean dist

dist: prov-dist node-dist

prov-dist:
	@@rm -rf "${BUILD_DIR}/${DIST_DIR_PROV}"
	@@rm -rf "${BUILD_DIR}/${DIST_DIR_PROV}.tar.gz"
	@@mkdir -p "${BUILD_DIR}/${DIST_DIR_PROV}/components"
	@@cp -rf ./components/common "${BUILD_DIR}/${DIST_DIR_PROV}/components"
	@@cp -rf ./prov "${BUILD_DIR}/${DIST_DIR_PROV}"
	@@cd ${BUILD_DIR} && tar -czf ./${DIST_DIR_PROV}.tar.gz ${DIST_DIR_PROV}
	@@echo "Created: ${BUILD_DIR}/${DIST_DIR_PROV}.tar.gz"

node-dist:
	@@rm -rf "${BUILD_DIR}/${DIST_DIR_NODE}"
	@@rm -rf "${BUILD_DIR}/${DIST_DIR_NODE}.tar.gz"
	@@mkdir -p "${BUILD_DIR}/${DIST_DIR_NODE}/components"
	@@cp -rf ./components/common "${BUILD_DIR}/${DIST_DIR_NODE}/components"
	@@cp -rf ./node "${BUILD_DIR}/${DIST_DIR_NODE}"
	@@cd ${BUILD_DIR} && tar -czf ./${DIST_DIR_NODE}.tar.gz ${DIST_DIR_NODE}
	@@echo "Created: ${BUILD_DIR}/${DIST_DIR_NODE}.tar.gz"

clean:
	rm -rf ${BUILD_DIR}
