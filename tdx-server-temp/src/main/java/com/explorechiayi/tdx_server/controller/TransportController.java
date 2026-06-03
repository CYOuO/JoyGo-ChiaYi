package com.explorechiayi.tdx_server.controller;

import com.explorechiayi.tdx_server.service.TdxService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

@RestController
@RequestMapping("/api/transport")
public class TransportController {

    @Autowired
    private TdxService tdxService;

    @GetMapping("/tra/liveboard/{stationId}")
    public Map<String, Object> getTraLiveBoard(@PathVariable String stationId) {
        return tdxService.getTraLiveBoard(stationId);
    }

    @GetMapping("/tra/od")
    public Map<String, Object> getTraOD(@RequestParam String origin, @RequestParam String dest, @RequestParam String date) {
        return tdxService.getTraOD(origin, dest, date);
    }

    @GetMapping("/thsr/od")
    public Map<String, Object> getThsrOD(@RequestParam String origin, @RequestParam String dest, @RequestParam String date) {
        return tdxService.getThsrOD(origin, dest, date);
    }

    @GetMapping("/youbike")
    public Map<String, Object> getYoubike() {
        return tdxService.getYoubikeDynamic();
    }

    @GetMapping("/bus/stop/{city}")
    public Map<String, Object> getBusStop(@PathVariable String city, @RequestParam String q) {
        return tdxService.getBusStopSearch(city, q);
    }

    @GetMapping("/bus/{city}/{routeName}")
    public Map<String, Object> getBus(@PathVariable String city, @PathVariable String routeName) {
        return tdxService.getBusDynamic(city, routeName);
    }

    @GetMapping("/tra/train/{trainNo}")
    public Map<String, Object> getTraTrainStops(@PathVariable String trainNo, @RequestParam String date) {
        return tdxService.getTraTrainStops(trainNo, date);
    }

    @GetMapping("/thsr/train/{trainNo}")
    public Map<String, Object> getThsrTrainStops(@PathVariable String trainNo, @RequestParam String date) {
        return tdxService.getThsrTrainStops(trainNo, date);
    }
    
    @GetMapping("/bus/gps/{city}/{routeName}")
    public Map<String, Object> getBusGps(@PathVariable String city, @PathVariable String routeName) {
        return tdxService.getBusRealTimePosition(city, routeName);
    }

    @GetMapping("/bus/nearby")
    public Map<String, Object> getNearbyBusStops(
            @RequestParam String city,
            @RequestParam double lat,
            @RequestParam double lng,
            @RequestParam(defaultValue = "500") int radius) {
        return tdxService.getNearbyBusStops(city, lat, lng, radius);
    }

    @GetMapping("/weather/{cityType}")
    public Map<String, Object> getWeather(@PathVariable String cityType) {
        // cityType 可以傳入 "Chiayi" 或 "ChiayiCounty"
        return tdxService.getWeeklyWeather(cityType);
    }
}