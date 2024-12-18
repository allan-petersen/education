package com.frankmoley.lil.landonhotel.web.controller;

import com.frankmoley.lil.landonhotel.service.RoomReservationService;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;

@Controller
public class ReservationController {

    private final RoomReservationService roomReservationService;

    public ReservationController(final RoomReservationService roomReservationService) {
        this.roomReservationService = roomReservationService ;
    }

    // Show form
    @RequestMapping("/reservations")
    public String showForm() {
        return "reservation-list";
    }

    @PostMapping("/reserve")
    public String getReservationsByDate(Model model, @RequestParam(value= "reservationDate", required = false) @DateTimeFormat(pattern = "yyyy-MM-dd") String date) {
        model.addAttribute("reservations", roomReservationService.getRoomReservationsForDate(date));
        // Name of the html template
        return "reservation-list";
    }

    /*
    @GetMapping
    public String getReservationsByDate(Model model, @RequestParam(value = "date", required = false) String date) {
            model.addAttribute("reservations", roomReservationService.getRoomReservationsForDate(date));
            // Name of the html template
            return "reservation-list";
    }

     */

}
