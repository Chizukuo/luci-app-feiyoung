module("luci.controller.feiyoung", package.seeall)

function index()
	if not nixio.fs.access("/etc/config/feiyoung") then
		return
	end

	entry({"admin", "services", "feiyoung"}, view("feiyoung/general"), _("FeiYoung Network"), 60)
end
